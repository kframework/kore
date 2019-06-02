{-|
Module      : Kore.Step.Function.Evaluator
Description : Evaluates functions in a pattern.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Function.Evaluator
    ( evaluateApplication
    , evaluatePattern
    ) where

import           Control.Exception
                 ( assert )
import qualified Data.Functor.Foldable as Recursive
import qualified Data.Map as Map
import           Data.Maybe
                 ( fromMaybe )
import           Data.Reflection
                 ( give )
import qualified Data.Text as Text

import qualified Kore.Attribute.Pattern as Attribute
import           Kore.Attribute.Symbol
                 ( Hook (..), StepperAttributes, isSortInjection_ )
import qualified Kore.Attribute.Symbol as Attribute
import           Kore.Debug
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools (..), SmtMetadataTools )
import qualified Kore.Internal.MultiOr as MultiOr
                 ( flatten, merge, mergeAll )
import           Kore.Internal.OrPattern
                 ( OrPattern )
import qualified Kore.Internal.OrPattern as OrPattern
import           Kore.Internal.Pattern
                 ( Conditional (..), Pattern, Predicate )
import qualified Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
import           Kore.Step.Axiom.Identifier
                 ( AxiomIdentifier )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
                 ( extract )
import qualified Kore.Step.Merging.OrPattern as OrPattern
import           Kore.Step.Simplification.Data as AttemptedAxiom
                 ( AttemptedAxiom (..) )
import           Kore.Step.Simplification.Data as Simplifier
import qualified Kore.Step.Simplification.Data as AttemptedAxiomResults
                 ( AttemptedAxiomResults (..) )
import qualified Kore.Step.Simplification.Data as BranchT
                 ( gather )
import qualified Kore.Step.Simplification.Pattern as Pattern
import           Kore.Unparser
import           Kore.Variables.Fresh

{-| Evaluates functions on an application pattern.
-}
evaluateApplication
    ::  forall variable.
        ( Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => Predicate variable
    -- ^ Aggregated children predicate and substitution.
    -> CofreeF
        (Application SymbolOrAlias)
        (Attribute.Pattern variable)
        (TermLike variable)
    -- ^ The pattern to be evaluated
    -> Simplifier (OrPattern variable)
evaluateApplication
    childrenPredicate
    (valid :< app)
  = do
    tools <- Simplifier.askMetadataTools
    substitutionSimplifier <- Simplifier.askSimplifierPredicate
    simplifier <- Simplifier.askSimplifierTermLike
    axiomIdToEvaluator <- Simplifier.askSimplifierAxioms
    let
        afterInj = evaluateSortInjection tools app
        Application { applicationSymbolOrAlias = appHead } = afterInj
        SymbolOrAlias { symbolOrAliasConstructor = symbolId } = appHead
        appPattern = Recursive.embed (valid :< ApplicationF afterInj)

        maybeEvaluatedPattSimplifier =
            maybeEvaluatePattern
                substitutionSimplifier
                simplifier
                axiomIdToEvaluator
                childrenPredicate
                appPattern
                unchanged
        unchangedPatt =
            Conditional
                { term         = appPattern
                , predicate    = predicate
                , substitution = substitution
                }
          where
            Conditional { term = (), predicate, substitution } =
                childrenPredicate
        unchanged = OrPattern.fromPattern unchangedPatt

        getSymbolHook = getHook . Attribute.hook . symAttributes tools
        getAppHookString = Text.unpack <$> getSymbolHook appHead

    case maybeEvaluatedPattSimplifier of
        Nothing
          | Just hook <- getAppHookString
          , not(null axiomIdToEvaluator) ->
            error
                (   "Attempting to evaluate unimplemented hooked operation "
                ++  hook ++ ".\nSymbol: " ++ getIdForError symbolId
                )
          | otherwise ->
            return unchanged
        Just evaluatedPattSimplifier -> evaluatedPattSimplifier

{-| Evaluates axioms on patterns.
-}
evaluatePattern
    ::  forall variable .
        ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from axiom IDs to axiom evaluators
    -> Predicate variable
    -- ^ Aggregated children predicate and substitution.
    -> TermLike variable
    -- ^ The pattern to be evaluated
    -> OrPattern variable
    -- ^ The default value
    -> Simplifier (OrPattern variable)
evaluatePattern
    substitutionSimplifier
    simplifier
    axiomIdToEvaluator
    childrenPredicate
    patt
    defaultValue
  =
    fromMaybe
        (return defaultValue)
        (maybeEvaluatePattern
            substitutionSimplifier
            simplifier
            axiomIdToEvaluator
            childrenPredicate
            patt
            defaultValue
        )

{-| Evaluates axioms on patterns.

Returns Nothing if there is no axiom for the pattern's identifier.
-}
maybeEvaluatePattern
    ::  forall variable .
        ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from axiom IDs to axiom evaluators
    -> Predicate variable
    -- ^ Aggregated children predicate and substitution.
    -> TermLike variable
    -- ^ The pattern to be evaluated
    -> OrPattern variable
    -- ^ The default value
    -> Maybe (Simplifier (OrPattern variable))
maybeEvaluatePattern
    substitutionSimplifier
    simplifier
    axiomIdToEvaluator
    childrenPredicate
    patt
    defaultValue
  =
    case maybeEvaluator of
        Nothing -> Nothing
        Just (BuiltinAndAxiomSimplifier evaluator) ->
            Just
            $ traceNonErrorMonad
                D_Function_evaluatePattern
                [ debugArg "axiomIdentifier" identifier ]
            $ do
                result <-
                    evaluator
                        substitutionSimplifier
                        simplifier
                        axiomIdToEvaluator
                        patt
                flattened <- case result of
                    AttemptedAxiom.NotApplicable ->
                        return AttemptedAxiom.NotApplicable
                    AttemptedAxiom.Applied AttemptedAxiomResults
                        { results = orResults
                        , remainders = orRemainders
                        } -> do
                            simplified <- mapM simplifyIfNeeded orResults
                            return
                                (AttemptedAxiom.Applied AttemptedAxiomResults
                                    { results =
                                        MultiOr.flatten simplified
                                    , remainders = orRemainders
                                    }
                                )
                merged <-
                    mergeWithConditionAndSubstitution
                        childrenPredicate
                        flattened
                case merged of
                    AttemptedAxiom.NotApplicable -> return defaultValue
                    AttemptedAxiom.Applied attemptResults ->
                        return $ MultiOr.merge results remainders
                      where
                        AttemptedAxiomResults { results, remainders } =
                            attemptResults
  where
    identifier :: Maybe AxiomIdentifier
    identifier = AxiomIdentifier.extract patt

    maybeEvaluator :: Maybe BuiltinAndAxiomSimplifier
    maybeEvaluator = do
        identifier' <- identifier
        Map.lookup identifier' axiomIdToEvaluator

    unchangedPatt =
        Conditional
            { term         = patt
            , predicate    = predicate
            , substitution = substitution
            }
      where
        Conditional { term = (), predicate, substitution } = childrenPredicate

    simplifyIfNeeded :: Pattern variable -> Simplifier (OrPattern variable)
    simplifyIfNeeded toSimplify
      | toSimplify == unchangedPatt =
        return (OrPattern.fromPattern unchangedPatt)
      | otherwise =
        reevaluateFunctions toSimplify

evaluateSortInjection
    :: Ord variable
    => SmtMetadataTools StepperAttributes
    -> Application SymbolOrAlias (TermLike variable)
    -> Application SymbolOrAlias (TermLike variable)
evaluateSortInjection tools ap
  | give tools isSortInjection_ apHead
  = case apChild of
    App_ apHeadChild grandChildren
      | give tools isSortInjection_ apHeadChild ->
        let
            [fromSort', toSort'] = symbolOrAliasParams apHeadChild
            apHeadNew = updateSortInjectionSource apHead fromSort'
            resultApp = apHeadNew grandChildren
        in
            assert (toSort' == fromSort) $
                ( resultApp

                )
    _ -> ap
  | otherwise = ap
  where
    apHead = applicationSymbolOrAlias ap
    [fromSort, _] = symbolOrAliasParams apHead
    [apChild] = applicationChildren ap
    updateSortInjectionSource head1 fromSort1 children =
        Application
            { applicationSymbolOrAlias =
                head1 { symbolOrAliasParams = [fromSort1, toSort1] }
            , applicationChildren = children
            }
      where
        [_, toSort1] = symbolOrAliasParams head1

{-| 'reevaluateFunctions' re-evaluates functions after a user-defined function
was evaluated.
-}
reevaluateFunctions
    ::  ( SortedVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        )
    => Pattern variable
    -- ^ Function evaluation result.
    -> Simplifier (OrPattern variable)
reevaluateFunctions rewriting = do
    pattOr <- simplifyTerm (Pattern.term rewriting)
    mergedPatt <-
        OrPattern.mergeWithPredicate (Pattern.withoutTerm rewriting) pattOr
    orResults <- BranchT.gather $ traverse Pattern.simplifyPredicate mergedPatt
    return (MultiOr.mergeAll orResults)

{-| Ands the given condition-substitution to the given function evaluation.
-}
mergeWithConditionAndSubstitution
    ::  ( Ord variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , SortedVariable variable
        )
    => Predicate variable
    -- ^ Condition and substitution to add.
    -> AttemptedAxiom variable
    -- ^ AttemptedAxiom to which the condition should be added.
    -> Simplifier (AttemptedAxiom variable)
mergeWithConditionAndSubstitution _ AttemptedAxiom.NotApplicable =
    return AttemptedAxiom.NotApplicable
mergeWithConditionAndSubstitution
    toMerge
    (AttemptedAxiom.Applied AttemptedAxiomResults { results, remainders })
  = do
    evaluatedResults <- OrPattern.mergeWithPredicate toMerge results
    evaluatedRemainders <- OrPattern.mergeWithPredicate toMerge remainders
    return $ AttemptedAxiom.Applied AttemptedAxiomResults
        { results = evaluatedResults
        , remainders = evaluatedRemainders
        }
