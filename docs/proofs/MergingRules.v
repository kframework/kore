Lemma combine_direct
  (p1 q1 p2 q2 : var -> Prop)
  (i j : nat)
  (H1 : forall x, p1  x -> q1 x)
  (H2 : forall x, p2 x -> q2 x)
  : forall (c : nat) x y,  (c = i /\ p1 x) \/ (c = j /\ p2 y) -> (c = i /\ q1 x) \/ (c = j /\ q2 y).
Proof.
  intros c x y [[Hc Hp1] | [Hc Hp2]].
  - left. split; try assumption. apply (H1 x Hp1).
  - right. split; try assumption. apply (H2 y Hp2).
Qed.

Lemma combine_reverse1
  (p1 q1 p2 q2 : var -> Prop)
  (i j : nat)
  (Hnij : i <> j)
  (Hc12 : forall (c : nat) x y,  (c = i /\ p1 x) \/ (c = j /\ p2 y) -> (c = i /\ q1 x) \/ (c = j /\ q2 y))
  : forall x, p1 x -> q1 x
  .
Proof.
  intros x Hp1.
  specialize (Hc12 i x x).
  assert (Hip1 : i = i /\ p1 x) by (split; try reflexivity; assumption).
  assert (Hip12 : i = i /\ p1 x \/ i = j /\ p2 x) by (left; assumption).
  specialize (Hc12 Hip12).
  clear Hip1. clear Hip12.
  destruct Hc12 as [[Hi Hq1] | [Hi Hq2]].
  - assumption.
  - contradiction.
Qed.


Lemma combine_reverse2
  (p1 q1 p2 q2 : var -> Prop)
  (i j : nat)
  (Hnij : i <> j)
  (Hc12 : forall (c : nat) x y,  (c = i /\ p1 x) \/ (c = j /\ p2 y) -> (c = i /\ q1 x) \/ (c = j /\ q2 y))
  : forall y, p2 y -> q2 y
  .
Proof.
  intros y Hp2.
  specialize (Hc12 j y y).
  assert (Hjp2 : j = j /\ p2 y) by (split; try reflexivity; assumption).
  assert (Hjp12 : j = i /\ p1 y \/ j = j /\ p2 y) by (right; assumption).
  specialize (Hc12 Hjp12).
  clear Hjp2. clear Hjp12.
  destruct Hc12 as [[Hj Hq1] | [Hj Hq2]].
  - symmetry in Hj. contradiction.
  - assumption.
Qed.

Theorem combine
  (p1 q1 p2 q2 : var -> Prop)
  (i j : nat)
  (Hnij : i <> j)
  : (forall x, p1  x -> q1 x) /\ (forall y, p2 y-> q2 y) 
    <-> forall (c : nat) x y,  (c = i /\ p1 x) \/ (c = j /\ p2 y) -> (c = i /\ q1 x) \/ (c = j /\ q2 y).
Proof.
  split.
  - intros [H1 H2]. apply combine_direct; assumption.
  - intro. split.
    + apply combine_reverse1 with p2 q2 i j; assumption.
    + apply combine_reverse2 with p1 q1 i j; assumption.
Qed.

