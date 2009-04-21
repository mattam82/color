(**
CoLoR, a Coq library on rewriting and termination.
See the COPYRIGHTS and LICENSE files.

- Frederic Blanqui, 2008-10-14

REN(CAP(_)) operation used in the DP framework.

Like ACap.capa except that variables are considered as aliens too.
*)

Set Implicit Arguments.

Require Import LogicUtil.
Require Import ACalls.
Require Import ATrs.
Require Import VecUtil.
Require Import ListUtil.
Require Import NatUtil.
Require Import RelUtil.

Section S.

Variable Sig : Signature.

Notation term := (term Sig). Notation terms := (vector term).

(***********************************************************************)
(** we first defined a generic cap as a triple (k,f,v) where
- k is the number of aliens
- f is a function which, given a vector v of k terms, returns the cap
with the ith alien replaced by the ith term of v
- v is the vector of the k aliens

the generic cap of a term is computed by the function capa below
its property is: if capa(t) = (k,f,v) then f(v)=t

f acts as an abstract context with k holes *)

Definition Cap := sigS (fun k => ((terms k -> term) * terms k)%type).

Notation Caps := (vector Cap).

Definition mkCap := @existS nat (fun k => ((terms k -> term) * terms k)%type).

Definition fcap (c : Cap) := fst (projS2 c).
Definition aliens (c : Cap) := snd (projS2 c).

(* total number of aliens of a vector of caps *)

Fixpoint sum n (cs : Caps n) {struct cs} : nat :=
  match cs with
    | Vnil => 0
    | Vcons c _ cs' => projS1 c + sum cs'
  end.

(* concatenation of all the aliens of a vector of caps *)

Fixpoint conc n (cs : Caps n) {struct cs} : terms (sum cs) :=
  match cs as cs return terms (sum cs) with
    | Vnil => Vnil
    | Vcons c _ cs' => Vapp (aliens c) (conc cs')
  end.

Lemma in_conc : forall u n (cs : Caps n), Vin u (conc cs) ->
  exists c, Vin c cs /\ Vin u (aliens c).

Proof.
induction cs; simpl; intros. contradiction.
assert (Vin u (aliens a) \/ Vin u (conc cs)). apply Vin_app. assumption.
destruct H0. exists a. auto.
assert (exists c, Vin c cs /\ Vin u (aliens c)). apply IHcs. assumption.
destruct H1 as [c]. exists c. intuition.
Qed.

Implicit Arguments in_conc [u n cs].

(* given a vector cs of caps and a vector ts of (sum cs) terms, this
function breaks ts in vectors of size the number of aliens of every
cap of cs, apply every fcap to the corresponding vector, and
concatenate all the results *)

Fixpoint Vmap_sum n (cs : Caps n) {struct cs} : terms (sum cs) -> terms n :=
  match cs as cs in vector _ n return terms (sum cs) -> terms n with
    | Vnil => fun _ => Vnil
    | Vcons c _ cs' => fun ts =>
      let (hd,tl) := Vbreak ts in Vcons (fcap c hd) (Vmap_sum cs' tl)
  end.

(***********************************************************************)
(** function computing the generic cap of a term *)

Notation rule := (@rule Sig). Notation rules := (list rule).

Variable R : rules.

Fixpoint capa (t : term) : Cap :=
  match t with
    | Var x => mkCap (fun v => Vnth v (lt_O_Sn 0), Vcons t Vnil)
    | Fun f ts =>
      let fix capas n (ts : terms n) {struct ts} : Caps n :=
	match ts in vector _ n return Caps n with
	  | Vnil => Vnil
	  | Vcons t n' ts' => Vcons (capa t) (capas n' ts')
	end
        in if defined f R
	  then mkCap (fun v => Vnth v (lt_O_Sn 0), Vcons t Vnil)
	  else let cs := capas (arity f) ts in
	    mkCap (fun v => Fun f (Vmap_sum cs v), conc cs)
end.

Lemma capa_fun : forall f ts, capa (Fun f ts) =
  if defined f R
  then mkCap (fun v => Vnth v (lt_O_Sn 0), Vcons (Fun f ts) Vnil)
  else let cs := Vmap capa ts in
    mkCap (fun v => Fun f (Vmap_sum cs v), conc cs).

Proof.
intros. reflexivity.
Qed.

(***********************************************************************)
(** number of aliens of a term *)

Definition nb_aliens t := projS1 (capa t).

Definition nb_aliens_vec n (ts : terms n) := sum (Vmap capa ts).

Lemma nb_aliens_cons : forall t n (ts : terms n),
  nb_aliens_vec (Vcons t ts) = nb_aliens t + nb_aliens_vec ts.

Proof.
refl.
Qed.

Lemma nb_aliens_fun : forall f ts,
  nb_aliens (Fun f ts) = if defined f R then 1 else nb_aliens_vec ts.

Proof.
intros. unfold nb_aliens, nb_aliens_vec. rewrite capa_fun.
case (defined f R); refl.
Qed.

(***********************************************************************)
(** concrete cap: it is obtained by applying fcap to a sequence of fresh
variables *)

Definition ren_cap k t := fcap (capa t) (fresh Sig k (nb_aliens t)).

Fixpoint ren_caps k n (ts : terms n) : terms n :=
  match ts in vector _ n return terms n with
  | Vnil => Vnil
  | Vcons t n' ts =>
    Vcons (ren_cap k t) (ren_caps (k + nb_aliens t) ts)
  end.

Lemma ren_caps_eq : forall n (ts : terms n) k,
  Vmap_sum (Vmap capa ts) (fresh Sig k (sum (Vmap capa ts)))
  =  ren_caps k ts.

Proof.
induction ts; simpl; intros. refl. rewrite Vbreak_fresh. apply Vcons_eq. refl.
rewrite IHts. refl.
Qed.

Lemma ren_cap_fun : forall f ts k,
  ren_cap k (Fun f ts) = if defined f R then Var k else Fun f (ren_caps k ts).

Proof.
intros. unfold ren_cap, nb_aliens. rewrite capa_fun. case (defined f R). refl.
unfold fcap. simpl. apply args_eq. apply ren_caps_eq.
Qed.
 
(***********************************************************************)
(** relation wrt variables *)

Lemma vars_ren_cap : forall x t k,
  In x (vars (ren_cap k t)) -> k <= x /\ x < k + nb_aliens t.

Proof.
intros x t; pattern t; apply term_ind with (Q := fun n (ts : terms n) =>
  forall k, In x (vars_vec (ren_caps k ts)) ->
  k <= x /\ x < k + nb_aliens_vec ts); clear t.
(* Var *)
unfold nb_aliens. simpl. intuition.
(* Fun *)
intros f ts H k0. rewrite ren_cap_fun. unfold nb_aliens. rewrite capa_fun.
case (defined f R). simpl. intuition. rewrite vars_fun. simpl. exact (H k0).
(* Vnil *)
simpl. intuition.
(* Vcons *)
intros t n ts h1 h2 k0. rewrite nb_aliens_cons. simpl. rewrite in_app.
intro. destruct H. ded (h1 _ H). omega. ded (h2 _ H). omega.
Qed.

Implicit Arguments vars_ren_cap [x t k].

Lemma vars_ren_caps : forall x n (ts : terms n) k,
  In x (vars_vec (ren_caps k ts)) -> k <= x /\ x < k + nb_aliens_vec ts.

Proof.
induction ts.
(* Vnil *)
simpl. intuition.
(* Vcons *)
simpl. intro. rewrite in_app. rewrite nb_aliens_cons. intro. destruct H.
ded (vars_ren_cap H). omega. ded (IHts _ H). omega.
Qed.

Implicit Arguments vars_ren_caps [x n ts k].

(***********************************************************************)
(** relation wrt substitution *)

Ltac single_tac x t :=
  exists (single x t); split; [single
  | unfold single, nb_aliens; simpl;
    let y := fresh "y" in intro y; intro;
    case_nat_eq x y; [absurd_arith | refl]].

Notation In_dec := (In_dec eq_nat_dec).

Lemma ren_cap_intro : forall t k, exists s, t = sub s (ren_cap k t)
  /\ forall x, x < k \/ x >= k + nb_aliens t -> s x = Var x.

Proof.
intro t; pattern t; apply term_ind with (Q := fun n (ts : terms n) =>
  forall k, exists s, ts = Vmap (sub s) (ren_caps k ts)
  /\ forall x, x < k \/ x >= k + nb_aliens_vec ts -> s x = Var x);
  clear t; intros.
(* Var *)
simpl. single_tac k (@Var Sig x).
(* Fun *)
rewrite nb_aliens_fun. rewrite ren_cap_fun. case (defined f R).
single_tac k (Fun f v). destruct (H k) as [s]. exists s. rewrite sub_fun.
intuition. rewrite <- H1. refl.
(* Vnil *)
exists (fun x => Var x). intuition.
(* Vcons *)
simpl. destruct (H k) as [s1]. destruct H1 as [H1 H1'].
destruct (H0 (k + nb_aliens t)) as [s2]. destruct H2 as [H2 H2']. 
set (s := fun x => match In_dec x (vars (ren_cap k t)) with
  | left _ => s1 x | right _ => s2 x end). exists s.
assert (sub s (ren_cap k t) = sub s1 (ren_cap k t)). apply sub_eq. intros.
unfold s. case (In_dec x (vars (ren_cap k t))); intro. refl.
intuition. rewrite H3. rewrite <- H1.
assert (Vmap (sub s) (ren_caps (k + nb_aliens t) v)
  = Vmap (sub s2) (ren_caps (k + nb_aliens t) v)). apply Vmap_sub_eq. intros.
ded (vars_ren_caps H4). unfold s. case (In_dec x (vars (ren_cap k t))); intro.
ded (vars_ren_cap i). absurd_arith. refl. rewrite H4. rewrite <- H2.
split. refl. rewrite nb_aliens_cons. intros. unfold s.
case (In_dec x (vars (ren_cap k t))); intro. ded (vars_ren_cap i).
absurd_arith. apply H2'. omega.
Qed.

Lemma ren_caps_intro : forall n (ts : terms n) k,
  exists s, ts = Vmap (sub s) (ren_caps k ts)
  /\ forall x, x < k \/ x >= k + nb_aliens_vec ts -> s x = Var x.

Proof.
induction ts; intro.
(* Vnil *)
exists (fun x => Var x). intuition.
(* Vcons *)
simpl. destruct (ren_cap_intro a k) as [s1]. destruct H as [H1 H1'].
destruct (IHts (k + nb_aliens a)) as [s2]. destruct H as [H2 H2'].
set (s := fun x => match In_dec x (vars (ren_cap k a)) with
  | left _ => s1 x | right _ => s2 x end). exists s.
assert (sub s (ren_cap k a) = sub s1 (ren_cap k a)). apply sub_eq. intros.
unfold s. case (In_dec x (vars (ren_cap k a))); intro. refl.
intuition. rewrite H. rewrite <- H1.
assert (Vmap (sub s) (ren_caps (k + nb_aliens a) ts)
  = Vmap (sub s2) (ren_caps (k + nb_aliens a) ts)). apply Vmap_sub_eq. intros.
ded (vars_ren_caps H0). unfold s. case (In_dec x (vars (ren_cap k a))); intro.
ded (vars_ren_cap i). absurd_arith. refl. rewrite H0. rewrite <- H2.
split. refl. rewrite nb_aliens_cons. intros. unfold s.
case (In_dec x (vars (ren_cap k a))); intro. ded (vars_ren_cap i).
absurd_arith. apply H2'. omega.
Qed.

Lemma ren_cap_sub_aux : forall s t k l,
  exists s', ren_cap k (sub s t) = sub s' (ren_cap l t)
          /\ forall x, x < l \/ x >= l + nb_aliens t -> s' x = Var x.

Proof.
intros s t; pattern t; apply term_ind with (Q := fun n (ts : terms n) =>
  forall k l, exists s',
  ren_caps k (Vmap (sub s) ts) = Vmap (sub s') (ren_caps l ts)
  /\ forall x, x < l \/ x >= l + nb_aliens_vec ts -> s' x = Var x);
  clear t; intros.
(* Var *)
simpl. single_tac l (ren_cap k (s x)).
(* Fun *)
rewrite sub_fun. repeat rewrite ren_cap_fun. rewrite nb_aliens_fun.
case (defined f R). simpl. single_tac l (@Var Sig k).
destruct (H k l) as [s']. destruct H0. exists s'. rewrite H0. rewrite sub_fun.
intuition.
(* Vnil *)
simpl. exists (fun x => Var x). auto.
(* Vcons *)
simpl. destruct (H k l) as [s1]. destruct H1 as [H1 H1']. rewrite H1.
destruct (H0 (k + nb_aliens (sub s t)) (l + nb_aliens t)) as [s2].
destruct H2 as [H2 H2']. rewrite H2.
set (s' := fun x => match In_dec x (vars (ren_cap l t)) with
  | left _ => s1 x | right _ => s2 x end). exists s'. split. apply Vcons_eq.
apply sub_eq. intros. unfold s'.
case (In_dec x (vars (ren_cap l t))); intro. refl. intuition.
apply Vmap_sub_eq. intros. ded (vars_ren_caps H3). unfold s'.
case (In_dec x (vars (ren_cap l t))); intro. ded (vars_ren_cap i).
absurd_arith. refl.
(* domain *)
rewrite nb_aliens_cons. intros. unfold s'.
case (In_dec x (vars (ren_cap l t))); intro. ded (vars_ren_cap i).
absurd_arith. apply H2'. omega.
Qed.

Lemma ren_cap_sub : forall s t k,
  exists s', ren_cap k (sub s t) = sub s' (ren_cap k t)
          /\ forall x, x < k \/ x >= k + nb_aliens t -> s' x = Var x.

Proof.
intros. apply ren_cap_sub_aux with (l := k).
Qed.

Lemma ren_caps_sub_aux : forall s n (ts : terms n) k l,
  exists s', ren_caps k (Vmap (sub s) ts) = Vmap (sub s') (ren_caps l ts)
  /\ forall x, x < l \/ x >= l + nb_aliens_vec ts -> s' x = Var x.

Proof.
induction ts; intros.
(* Vnil *)
simpl. exists (fun x => Var x). auto.
(* Vcons *)
simpl. destruct (ren_cap_sub_aux s a k l) as [s1]. destruct H as [H1 H1'].
rewrite H1.
destruct (IHts (k + nb_aliens (sub s a)) (l + nb_aliens a)) as [s2].
destruct H as [H2 H2']. rewrite H2.
set (s' := fun x => match In_dec x (vars (ren_cap l a)) with
  | left _ => s1 x | right _ => s2 x end). exists s'. split. apply Vcons_eq.
apply sub_eq. intros. unfold s'.
case (In_dec x (vars (ren_cap l a))); intro. refl. intuition.
apply Vmap_sub_eq. intros. ded (vars_ren_caps H). unfold s'.
case (In_dec x (vars (ren_cap l a))); intro. ded (vars_ren_cap i).
absurd_arith. refl.
(* domain *)
rewrite nb_aliens_cons. intros. unfold s'.
case (In_dec x (vars (ren_cap l a))); intro. ded (vars_ren_cap i).
absurd_arith. apply H2'. omega.
Qed.

Lemma ren_caps_sub : forall s n (ts : terms n) k,
  exists s', ren_caps k (Vmap (sub s) ts) = Vmap (sub s') (ren_caps k ts)
  /\ forall x, x < k \/ x >= k + nb_aliens_vec ts -> s' x = Var x.

Proof.
intros. apply ren_caps_sub_aux with (l := k).
Qed.

(***********************************************************************)
(** idempotence *)

Lemma nb_aliens_ren_cap : forall t k, nb_aliens (ren_cap k t) = nb_aliens t.

Proof.
intro t; pattern t; apply term_ind with (Q := fun n (ts : terms n) =>
  forall k, nb_aliens_vec (ren_caps k ts) = nb_aliens_vec ts);
  clear t; intros; auto.
(* Fun *)
rewrite ren_cap_fun. rewrite nb_aliens_fun. case_eq (defined f R). refl.
rewrite nb_aliens_fun. rewrite H0. auto.
(* Vcons *)
simpl. repeat rewrite nb_aliens_cons. auto.
Qed.

Lemma ren_cap_idem : forall t k l, ren_cap k (ren_cap l t) = ren_cap k t.

Proof.
intro t; pattern t; apply term_ind with (Q := fun n (ts : terms n) =>
  forall k l, ren_caps k (ren_caps l ts) = ren_caps k ts);
  clear t; intros; auto.
(* Fun *)
repeat rewrite ren_cap_fun. case_eq (defined f R). refl. rewrite ren_cap_fun.
rewrite H0. rewrite H. refl.
(* Vcons *)
simpl. rewrite H. rewrite H0. rewrite nb_aliens_ren_cap. refl.
Qed.

(***********************************************************************)
(** relation with vector operations *)

Lemma ren_caps_cast : forall n1 (ts : terms n1) n2 (e : n1=n2) k,
  ren_caps k (Vcast ts e) = Vcast (ren_caps k ts) e.

Proof.
induction ts; intros; destruct n2; try (refl || discr).
simpl. rewrite IHts. refl.
Qed.

Lemma ren_caps_app : forall n2 (v2 : terms n2) n1 (v1 : terms n1) k,
  ren_caps k (Vapp v1 v2)
  = Vapp (ren_caps k v1) (ren_caps (k + nb_aliens_vec v1) v2).

Proof.
induction v1; simpl; intros. unfold nb_aliens_vec. simpl. rewrite plus_0_r.
refl. rewrite nb_aliens_cons. rewrite plus_assoc. rewrite <- IHv1. refl.
Qed.

(***********************************************************************)
(** relation with reduction *)

Variable hyp : forallb (@is_notvar_lhs Sig) R = true.

Lemma red_sub_ren_cap : forall u v,
  red R u v -> forall k, exists s, v = sub s (ren_cap k u).

Proof.
intros u v H. redtac. subst. elim c; clear c; simpl; intros.
(* Hole *)
destruct l. is_var_lhs. assert (defined f R = true).
eapply lhs_fun_defined. apply lr. rewrite sub_fun. rewrite ren_cap_fun.
rewrite H. exists_single k (sub s r).
(* Cont *)
rewrite ren_cap_fun. case (defined f R). simpl.
exists_single k (Fun f (Vcast (Vapp v (Vcons (fill c (sub s r)) v0)) e)).
rewrite ren_caps_cast. rewrite ren_caps_app. simpl ren_caps.
destruct (ren_caps_intro v k) as [s1]. destruct H0 as [H0 H0'].
destruct (H (k + nb_aliens_vec v)) as [s2].
destruct (ren_caps_intro v0
  (k + nb_aliens_vec v + nb_aliens (fill c (sub s l)))) as [s3].
destruct H2 as [H2 H2'].
set (s' := fun x => match In_dec x (vars_vec (ren_caps k v)) with
  | left _ => s1 x | right _ => match
  In_dec x (vars (ren_cap (k + nb_aliens_vec v) (fill c (sub s l)))) with
  | left _ => s2 x | right _ => s3 x end end). exists s'.
rewrite sub_fun. apply args_eq. rewrite Vmap_cast. rewrite Vmap_app. simpl.
apply Vcast_eq. apply Vapp_eq. transitivity (Vmap (sub s1) (ren_caps k v)).
hyp. apply Vmap_sub_eq. intros. ded (vars_ren_caps H3). unfold s'.
case (In_dec x (vars_vec (ren_caps k v))); intro. refl. intuition.
apply Vcons_eq. rewrite H1. apply sub_eq. intros. ded (vars_ren_cap H3).
unfold s'. case (In_dec x (vars_vec (ren_caps k v))); intro.
ded (vars_ren_caps i0). absurd_arith. case
  (In_dec x (vars (ren_cap (k + nb_aliens_vec v) (fill c (sub s l)))));
  intro. refl. intuition.
transitivity (Vmap (sub s3)
  (ren_caps (k + nb_aliens_vec v + nb_aliens (fill c (sub s l))) v0)).
hyp. apply Vmap_sub_eq. intros. ded (vars_ren_caps H3). unfold s'.
case (In_dec x (vars_vec (ren_caps k v))); intro.
ded (vars_ren_caps i0). absurd_arith. case
  (In_dec x (vars (ren_cap (k + nb_aliens_vec v) (fill c (sub s l)))));
  intro. ded (vars_ren_cap i0). absurd_arith. refl.
Qed.

Lemma rtc_red_sub_ren_cap : forall k u v,
  red R # u v -> exists s, v = sub s (ren_cap k u).

Proof.
induction 1; intros. apply red_sub_ren_cap. hyp.
destruct (ren_cap_intro x k). exists x0. intuition.
destruct IHclos_refl_trans1. destruct IHclos_refl_trans2. subst.
destruct (ren_cap_sub x0 (ren_cap k x) k). destruct H1. rewrite H1.
rewrite ren_cap_idem. rewrite sub_sub. exists (comp x1 x2). refl.
Qed.

End S.

Implicit Arguments vars_ren_cap [Sig R x t k].
Implicit Arguments vars_ren_caps [Sig R x n ts k].
