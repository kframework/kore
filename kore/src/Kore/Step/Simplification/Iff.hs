{-|
Module      : Kore.Step.Simplification.Iff
Description : Tools for Iff pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Iff
    ( makeEvaluate
    , simplify
    , simplifyEvaluated
    ) where

import           Kore.AST.Common
                 ( Iff (..) )
import           Kore.AST.Valid
import qualified Kore.Attribute.Symbol as Attribute
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import           Kore.Predicate.Predicate
                 ( makeAndPredicate, makeIffPredicate, makeTruePredicate )
import           Kore.Step.Axiom.Data
                 ( BuiltinAndAxiomSimplifierMap )
import qualified Kore.Step.Or as Or
import           Kore.Step.Pattern as Pattern
import qualified Kore.Step.Representation.MultiOr as MultiOr
                 ( extractPatterns, make )
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier, SimplificationProof (..),
                 Simplifier, StepPatternSimplifier )
import qualified Kore.Step.Simplification.Not as Not
                 ( makeEvaluate, simplifyEvaluated )
import           Kore.Unparser
import           Kore.Variables.Fresh
                 ( FreshVariable )

{-|'simplify' simplifies an 'Iff' pattern with 'Or.Pattern'
children.

Right now this has special cases only for top and bottom children
and for children with top terms.
-}
simplify
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        )
    => SmtMetadataTools Attribute.Symbol
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object
    -> Iff Object (Or.Pattern Object variable)
    -> Simplifier
        (Or.Pattern Object variable, SimplificationProof Object)
simplify
    tools
    predicateSimplifier
    termSimplifier
    axiomSimplifiers
    Iff
        { iffFirst = first
        , iffSecond = second
        }
  =
    fmap withProof $ simplifyEvaluated
        tools
        predicateSimplifier
        termSimplifier
        axiomSimplifiers
        first
        second
  where
    withProof a = (a, SimplificationProof)

{-| evaluates an 'Iff' given its two 'Or.Pattern' children.

See 'simplify' for detailed documentation.
-}
{- TODO (virgil): Preserve pattern sorts under simplification.

One way to preserve the required sort annotations is to make 'simplifyEvaluated'
take an argument of type

> CofreeF (Iff Object) (Valid Object) (Or.Pattern Object variable)

instead of two 'Or.Pattern' arguments. The type of 'makeEvaluate' may
be changed analogously. The 'Valid' annotation will eventually cache information
besides the pattern sort, which will make it even more useful to carry around.

-}
simplifyEvaluated
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        )
    => SmtMetadataTools Attribute.Symbol
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object
    -> Or.Pattern Object variable
    -> Or.Pattern Object variable
    -> Simplifier (Or.Pattern Object variable)
simplifyEvaluated
    tools
    predicateSimplifier
    termSimplifier
    axiomSimplifiers
    first
    second
  | Or.isTrue first = return second
  | Or.isFalse first =
    Not.simplifyEvaluated
        tools
        predicateSimplifier
        termSimplifier
        axiomSimplifiers
        second
  | Or.isTrue second = return first
  | Or.isFalse second =
    Not.simplifyEvaluated
        tools
        predicateSimplifier
        termSimplifier
        axiomSimplifiers
        first
  | otherwise =
    return $ case ( firstPatterns, secondPatterns ) of
        ([firstP], [secondP]) -> makeEvaluate firstP secondP
        _ ->
            makeEvaluate
                (Or.toExpandedPattern first)
                (Or.toExpandedPattern second)
  where
    firstPatterns = MultiOr.extractPatterns first
    secondPatterns = MultiOr.extractPatterns second

{-| evaluates an 'Iff' given its two 'Pattern' children.

See 'simplify' for detailed documentation.
-}
makeEvaluate
    ::  ( SortedVariable variable
        , Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        )
    => Pattern Object variable
    -> Pattern Object variable
    -> Or.Pattern Object variable
makeEvaluate first second
  | Pattern.isTop first = MultiOr.make [second]
  | Pattern.isBottom first = Not.makeEvaluate second
  | Pattern.isTop second = MultiOr.make [first]
  | Pattern.isBottom second = Not.makeEvaluate first
  | otherwise = makeEvaluateNonBoolIff first second

makeEvaluateNonBoolIff
    ::  ( SortedVariable variable
        , Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        )
    => Pattern Object variable
    -> Pattern Object variable
    -> Or.Pattern Object variable
makeEvaluateNonBoolIff
    patt1@Conditional
        { term = firstTerm
        , predicate = firstPredicate
        , substitution = firstSubstitution
        }
    patt2@Conditional
        { term = secondTerm
        , predicate = secondPredicate
        , substitution = secondSubstitution
        }
  | isTop firstTerm, isTop secondTerm
  =
    MultiOr.make
        [ Conditional
            { term = firstTerm
            , predicate =
                makeIffPredicate
                    (makeAndPredicate
                        firstPredicate
                        (substitutionToPredicate firstSubstitution))
                    (makeAndPredicate
                        secondPredicate
                        (substitutionToPredicate secondSubstitution)
                    )
            , substitution = mempty
            }
        ]
  | otherwise =
    MultiOr.make
        [ Conditional
            { term = mkIff
                (Pattern.toMLPattern patt1)
                (Pattern.toMLPattern patt2)
            , predicate = makeTruePredicate
            , substitution = mempty
            }
        ]
