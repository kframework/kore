{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

 -}

module Kore.Step.Remainder
    ( remainder
    , existentiallyQuantifyTarget
    ) where

import           Control.Applicative
                 ( Alternative (..) )
import qualified Data.Foldable as Foldable
import qualified Data.Set as Set

import           Kore.AST.Pure
import           Kore.AST.Valid
import           Kore.Predicate.Predicate
                 ( Predicate )
import qualified Kore.Predicate.Predicate as Predicate
import           Kore.Step.Conditional
                 ( Conditional (Conditional) )
import qualified Kore.Step.Pattern as Pattern
import           Kore.Step.Representation.MultiAnd
                 ( MultiAnd )
import qualified Kore.Step.Representation.MultiAnd as MultiAnd
import           Kore.Step.Representation.MultiOr
                 ( MultiOr )
import           Kore.Step.Representation.PredicateSubstitution
                 ( PredicateSubstitution )
import           Kore.Unification.Substitution
                 ( Substitution )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unparser
import           Kore.Variables.Target
                 ( Target )
import qualified Kore.Variables.Target as Target

{- | Negate the disjunction of unification solutions to form the /remainder/.

The /remainder/ is the parts of the initial configuration that is not matched
by any applied rule.

 -}
remainder
    ::  ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , SortedVariable variable
        )
    => MultiOr (PredicateSubstitution Object (Target variable))
    -> Predicate variable
remainder results =
    mkMultiAndPredicate $ mkNotExists conditions
  where
    conditions = mkMultiAndPredicate . unificationConditions <$> results
    mkNotExists = mkNotMultiOr . fmap existentiallyQuantifyTarget

-- | Existentially-quantify target (axiom) variables in the 'Predicate'.
existentiallyQuantifyTarget
    ::  ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , SortedVariable variable
        )
    => Predicate (Target variable)
    -> Predicate variable
existentiallyQuantifyTarget predicate =
    Predicate.mapVariables Target.unwrapVariable
    $ Predicate.makeMultipleExists freeTargetVariables predicate
  where
    freeTargetVariables =
        Set.filter Target.isTarget (Predicate.freeVariables predicate)

{- | Negate a disjunction of many terms.

@
  ¬ (φ₁ ∨ φ₂ ∨ ...) = ¬φ₁ ∧ ¬φ₂ ∧ ...
@

 -}
mkNotMultiOr
    ::  ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , SortedVariable variable
        )
    => MultiOr  (Predicate variable)
    -> MultiAnd (Predicate variable)
mkNotMultiOr = MultiAnd.make . map Predicate.makeNotPredicate . Foldable.toList

mkMultiAndPredicate
    ::  ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , SortedVariable variable
        )
    => MultiAnd (Predicate variable)
    ->           Predicate variable
mkMultiAndPredicate = Predicate.makeMultipleAndPredicate . Foldable.toList

{- | Represent the unification solution as a conjunction of predicates.
 -}
unificationConditions
    ::  ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , SortedVariable variable
        )
    => PredicateSubstitution Object (Target variable)
    -- ^ Unification solution
    -> MultiAnd (Predicate (Target variable))
unificationConditions Conditional { predicate, substitution } =
    pure predicate <|> substitutionConditions substitution'
  where
    substitution' = Substitution.filter Target.isNonTarget substitution

substitutionConditions
    ::  ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , SortedVariable variable
        )
    => Substitution variable
    -> MultiAnd (Predicate variable)
substitutionConditions subst =
    MultiAnd.make (substitutionCoverageWorker <$> Substitution.unwrap subst)
  where
    substitutionCoverageWorker (x, t) =
        Predicate.makeEqualsPredicate (mkVar x) t
