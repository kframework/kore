{-|
Module      : Kore.Step.Simplification.Exists
Description : Tools for Exists pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Exists
    ( simplify
    , makeEvaluate
    ) where

import qualified Control.Monad.Trans as Monad.Trans
import qualified Data.Map.Strict as Map
import           GHC.Stack
                 ( HasCallStack )

import           Kore.AST.Valid
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import qualified Kore.Predicate.Predicate as Syntax.Predicate
import           Kore.Step.Axiom.Data
                 ( BuiltinAndAxiomSimplifierMap )
import qualified Kore.Step.Conditional as Conditional
import           Kore.Step.OrPattern
                 ( OrPattern )
import qualified Kore.Step.OrPattern as OrPattern
import           Kore.Step.Pattern as Pattern
import qualified Kore.Step.Predicate as Predicate
import qualified Kore.Step.Representation.MultiOr as MultiOr
import           Kore.Step.Simplification.Data
                 ( BranchT, PredicateSimplifier, SimplificationProof (..),
                 Simplifier, TermLikeSimplifier, gather, scatter )
import qualified Kore.Step.Simplification.Pattern as Pattern
                 ( simplify )
import qualified Kore.Step.Substitution as Substitution
import           Kore.Step.TermLike as Pattern
import           Kore.Syntax.Exists
import qualified Kore.TopBottom as TopBottom
import           Kore.Unification.Substitution
                 ( Substitution )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unparser
import           Kore.Variables.Fresh


-- TODO: Move Exists up in the other simplifiers or something similar. Note
-- that it messes up top/bottom testing so moving it up must be done
-- immediately after evaluating the children.
{-|'simplify' simplifies an 'Exists' pattern with an 'OrPattern'
child.

The simplification of exists x . (pat and pred and subst) is equivalent to:

* If the subst contains an assignment for x, then substitute that in pat and
  pred, reevaluate them and return
  (reevaluated-pat and reevaluated-pred and subst-without-x).
* Otherwise, if x does not occur free in pat and pred, return
  (pat and pred and subst)
* Otherwise, if x does not occur free in pat, return
  (pat and (exists x . pred) and subst)
* Otherwise, if x does not occur free in pred, return
  ((exists x . pat) and pred and subst)
* Otherwise return
  ((exists x . pat and pred) and subst)
-}
simplify
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Simplifies patterns.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from axiom IDs to axiom evaluators
    -> Exists Sort variable (OrPattern variable)
    -> Simplifier
        ( OrPattern variable
        , SimplificationProof Object
        )
simplify
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    Exists { existsVariable = variable, existsChild = child }
  =
    simplifyEvaluated
        tools
        substitutionSimplifier
        simplifier
        axiomIdToSimplifier
        variable
        child

{- TODO (virgil): Preserve pattern sorts under simplification.

One way to preserve the required sort annotations is to make 'simplifyEvaluated'
take an argument of type

> CofreeF (Exists Sort) (Valid Object) (OrPattern variable)

instead of a 'variable' and an 'OrPattern' argument. The type of
'makeEvaluate' may be changed analogously. The 'Valid' annotation will
eventually cache information besides the pattern sort, which will make it even
more useful to carry around.

-}
simplifyEvaluated
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Simplifies patterns.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from axiom IDs to axiom evaluators
    -> variable
    -> OrPattern variable
    -> Simplifier
        (OrPattern variable, SimplificationProof Object)
simplifyEvaluated
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    variable
    simplified
  | OrPattern.isTrue simplified =
    return (simplified, SimplificationProof)
  | OrPattern.isFalse simplified =
    return (simplified, SimplificationProof)
  | otherwise = do
    (evaluated, _proofs) <-
        MultiOr.traverseFlattenWithPairs
            (makeEvaluate
                tools
                substitutionSimplifier
                simplifier
                axiomIdToSimplifier
                variable
            )
            simplified
    return ( evaluated, SimplificationProof )

{-| evaluates an 'Exists' given its two 'Pattern' children.

See 'simplify' for detailed documentation.
-}
makeEvaluate
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Simplifies patterns.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from axiom IDs to axiom evaluators
    -> variable
    -> Pattern variable
    -> Simplifier
        (OrPattern variable, SimplificationProof Object)
makeEvaluate
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    variable
    original
  = fmap (withProof . OrPattern.fromPatterns) $ gather $ do
    normalized <- normalize original
    let Conditional { substitution = normalizedSubstitution } = normalized
    case splitSubstitution variable normalizedSubstitution of
        (Left boundTerm, freeSubstitution) ->
            makeEvaluateBoundLeft
                tools
                substitutionSimplifier
                simplifier
                axiomIdToSimplifier
                variable
                boundTerm
                normalized { substitution = freeSubstitution }
        (Right boundSubstitution, freeSubstitution) ->
            makeEvaluateBoundRight
                variable
                freeSubstitution
                normalized { substitution = boundSubstitution }
  where
    withProof a = (a, SimplificationProof)
    normalize =
        Substitution.normalize
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier

{- | Existentially quantify a variable in the given 'Pattern'.

The variable was found on the left-hand side of a substitution and the given
term will be substituted everywhere. The variable may occur anywhere in the
'term' or 'predicate' of the 'Pattern', but not in the
'substitution'. The quantified variable must not occur free in the substituted
 term; an error is thrown if it is found.  The final result will not contain the
 quantified variable and thus the quantifier will actually be omitted.

See also: 'quantifyPattern'

 -}
makeEvaluateBoundLeft
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Simplifies patterns.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from axiom IDs to axiom evaluators
    -> variable  -- ^ quantified variable
    -> TermLike variable  -- ^ substituted term
    -> Pattern variable
    -> BranchT Simplifier (Pattern variable)
makeEvaluateBoundLeft
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    variable
    boundTerm
    normalized
  = withoutFreeVariable variable boundTerm $ do
        let
            boundSubstitution = Map.singleton variable boundTerm
            substituted =
                normalized
                    { term =
                        Pattern.substitute boundSubstitution
                        $ Conditional.term normalized
                    , predicate =
                        Syntax.Predicate.substitute boundSubstitution
                        $ Conditional.predicate normalized
                    }
        (results, _proof) <- Monad.Trans.lift $ simplify' substituted
        scatter results
  where
    simplify' =
        Pattern.simplify
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier

{- | Existentially quantify a variable in the given 'Pattern'.

The variable does not occur in the any equality in the free substitution. The
variable may occur anywhere in the 'term' or 'predicate' of the
'Pattern', but only on the right-hand side of an equality in the
'substitution'.

See also: 'quantifyPattern'

 -}
makeEvaluateBoundRight
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        )
    => variable  -- ^ variable to be quantified
    -> Substitution variable  -- ^ free substitution
    -> Pattern variable  -- ^ pattern to quantify
    -> BranchT Simplifier (Pattern variable)
makeEvaluateBoundRight
    variable
    freeSubstitution
    normalized
  = do
    TopBottom.guardAgainstBottom simplifiedPattern
    return simplifiedPattern
  where
    simplifiedPattern =
        Conditional.andCondition
            (quantifyPattern variable normalized)
            (Predicate.fromSubstitution freeSubstitution)

{- | Split the substitution on the given variable.

The substitution must be normalized and the normalization state is preserved.

The result is a pair of:

* Either the term bound to the variable (if the variable is on the 'Left' side
  of a substitution) or the substitutions that depend on the variable (if the
  variable is on the 'Right' side of a substitution). (These conditions are
  mutually exclusive for a normalized substitution.)
* The substitutions that do not depend on the variable at all.

 -}
splitSubstitution
    :: (HasCallStack, Ord variable)
    => variable
    -> Substitution variable
    ->  ( Either (TermLike variable) (Substitution variable)
        , Substitution variable
        )
splitSubstitution variable substitution =
    (bound, independent)
  where
    (dependent, independent) = Substitution.partition hasVariable substitution
    hasVariable variable' term =
        variable == variable' || Pattern.hasFreeVariable variable term
    bound =
        maybe (Right dependent) Left
        $ Map.lookup variable (Substitution.toMap dependent)

{- | Existentially quantify the variable an 'Pattern'.

The substitution is assumed to depend on the quantified variable. The quantifier
is lowered onto the 'term' or 'predicate' alone, or omitted, if possible.

 -}
quantifyPattern
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        )
    => variable
    -> Pattern variable
    -> Pattern variable
quantifyPattern variable Conditional { term, predicate, substitution }
  | quantifyTerm, quantifyPredicate =
      Conditional
        { term =
            mkExists variable
            $ mkAnd term
            $ Syntax.Predicate.unwrapPredicate predicate'
        , predicate = Syntax.Predicate.makeTruePredicate
        , substitution = mempty
        }
  | quantifyTerm =
      Conditional
        { term = mkExists variable term
        , predicate
        , substitution
        }
  | quantifyPredicate =
      Conditional
        { term
        , predicate = Syntax.Predicate.makeExistsPredicate variable predicate'
        , substitution = mempty
        }
  | otherwise = Conditional { term, predicate, substitution }
  where
    quantifyTerm = Pattern.hasFreeVariable variable term
    predicate' =
        Syntax.Predicate.makeAndPredicate predicate
        $ Syntax.Predicate.fromSubstitution substitution
    quantifyPredicate = Syntax.Predicate.hasFreeVariable variable predicate'
