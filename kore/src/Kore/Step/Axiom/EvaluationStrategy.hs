{-|
Module      : Kore.Step.Axiom.EvaluationStrategy
Description : Various strategies for axiom/builtin-based simplification.
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Axiom.EvaluationStrategy
    ( builtinEvaluation
    , definitionEvaluation
    , firstFullEvaluation
    , simplifierWithFallback
    ) where

import           Control.Monad
                 ( when )
import           Control.Monad.Trans.Except
import           Data.Maybe
                 ( isJust )
import qualified Data.Text as Text

import           Kore.AST.Common
                 ( SortedVariable (..), Variable )
import           Kore.AST.MetaOrObject
                 ( MetaOrObject, Object, OrdMetaOrObject, ShowMetaOrObject )
import           Kore.AST.Pure
                 ( asConcretePurePattern )
import           Kore.AST.Valid
                 ( pattern App_ )
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools (..) )
import           Kore.Step.Axiom.Data
                 ( AttemptedAxiom,
                 AttemptedAxiomResults (AttemptedAxiomResults),
                 BuiltinAndAxiomSimplifier (..), BuiltinAndAxiomSimplifierMap )
import qualified Kore.Step.Axiom.Data as AttemptedAxiomResults
                 ( AttemptedAxiomResults (..) )
import qualified Kore.Step.Axiom.Data as AttemptedAxiom
                 ( AttemptedAxiom (..) )
import           Kore.Step.Axiom.Matcher
                 ( unificationWithAppMatchOnTop )
import           Kore.Step.AxiomPatterns
                 ( EqualityRule (EqualityRule) )
import qualified Kore.Step.AxiomPatterns as RulePattern
import           Kore.Step.BaseStep
                 ( OrStepResult (OrStepResult),
                 UnificationProcedure (UnificationProcedure),
                 stepWithRemaindersForUnifier )
import qualified Kore.Step.BaseStep as OrStepResult
                 ( OrStepResult (..) )
import           Kore.Step.Pattern
                 ( StepPattern, asConcreteStepPattern )
import           Kore.Step.Representation.ExpandedPattern
                 ( ExpandedPattern )
import qualified Kore.Step.Representation.ExpandedPattern as ExpandedPattern
                 ( fromPurePattern )
import qualified Kore.Step.Representation.MultiOr as MultiOr
                 ( extractPatterns, make )
import qualified Kore.Step.Representation.OrOfExpandedPattern as OrOfExpandedPattern
                 ( isFalse )
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier, SimplificationProof (..),
                 Simplifier, StepPatternSimplifier (..) )
import qualified Kore.Step.Simplification.ExpandedPattern as ExpandedPattern
import           Kore.Step.StepperAttributes
                 ( Hook (..), StepperAttributes (..) )
import           Kore.Unparser
                 ( Unparse, unparseToString )
import           Kore.Variables.Fresh
                 ( FreshVariable )

import qualified Kore.Proof.Value as Value

{-|Describes whether simplifiers are allowed to return multiple results or not.
-}
data AcceptsMultipleResults = WithMultipleResults | OnlyOneResult
    deriving (Eq, Ord, Show)

{-|Converts 'AcceptsMultipleResults' to Bool.
-}
acceptsMultipleResults :: AcceptsMultipleResults -> Bool
acceptsMultipleResults WithMultipleResults = True
acceptsMultipleResults OnlyOneResult = False

{-| Creates an evaluator for a function from the full set of rules
that define it.
-}
definitionEvaluation
    :: [EqualityRule level Variable]
    -> BuiltinAndAxiomSimplifier level
definitionEvaluation rules =
    BuiltinAndAxiomSimplifier
        (evaluateWithDefinitionAxioms rules)

{-| Creates an evaluator that choses the result of the first evaluator that
returns Applicable.

If that result contains more than one pattern, or it contains a reminder,
the evaluation fails with 'error' (may change in the future).
-}
firstFullEvaluation
    :: [BuiltinAndAxiomSimplifier level]
    -> BuiltinAndAxiomSimplifier level
firstFullEvaluation simplifiers =
    BuiltinAndAxiomSimplifier
        (applyFirstSimplifierThatWorks simplifiers OnlyOneResult)

{-| Creates an evaluator that choses the result of the first evaluator if it
returns Applicable, otherwise returns the result of the second.
-}
simplifierWithFallback
    :: BuiltinAndAxiomSimplifier level
    -> BuiltinAndAxiomSimplifier level
    -> BuiltinAndAxiomSimplifier level
simplifierWithFallback first second =
    BuiltinAndAxiomSimplifier
        (applyFirstSimplifierThatWorks [first, second] WithMultipleResults)

{-| Wraps an evaluator for builtins. Will fail with error if there is no result
on concrete patterns.
-}
builtinEvaluation
    :: BuiltinAndAxiomSimplifier level
    -> BuiltinAndAxiomSimplifier level
builtinEvaluation evaluator =
    BuiltinAndAxiomSimplifier (evaluateBuiltin evaluator)


evaluateBuiltin
    :: forall variable level
    .   ( FreshVariable variable
        , MetaOrObject level
        , Ord (variable level)
        , OrdMetaOrObject variable
        , SortedVariable variable
        , Show (variable level)
        , Show (variable Object)
        , Unparse (variable level)
        , ShowMetaOrObject variable
        )
    => BuiltinAndAxiomSimplifier level
    -> MetadataTools level StepperAttributes
    -> PredicateSubstitutionSimplifier level
    -> StepPatternSimplifier level
    -> BuiltinAndAxiomSimplifierMap level
    -- ^ Map from axiom IDs to axiom evaluators
    -> StepPattern level variable
    -> Simplifier
        (AttemptedAxiom level variable, SimplificationProof level)
evaluateBuiltin
    (BuiltinAndAxiomSimplifier builtinEvaluator)
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    patt
  = do
    (result, _proof) <-
        builtinEvaluator
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            patt
    case result of
        AttemptedAxiom.NotApplicable
          | isPattConcrete
          , App_ appHead children <- patt
          , Just hook <- getAppHookString appHead
          , all isValue children ->
            error
                (   "Expecting hook " ++ hook
               ++  " to reduce concrete pattern\n\t"
                ++ show patt
                )
          | otherwise ->
            return (AttemptedAxiom.NotApplicable, SimplificationProof)
        AttemptedAxiom.Applied _ -> return (result, SimplificationProof)
  where
    isPattConcrete = isJust (asConcretePurePattern patt)
    isValue pat = isJust $
        Value.fromConcreteStepPattern tools =<< asConcreteStepPattern pat
    -- TODO(virgil): Send this from outside.
    getAppHookString appHead =
        Text.unpack <$> (getHook . hook . symAttributes tools) appHead

applyFirstSimplifierThatWorks
    :: forall variable level
    .   ( FreshVariable variable
        , MetaOrObject level
        , Ord (variable level)
        , OrdMetaOrObject variable
        , SortedVariable variable
        , Show (variable level)
        , Show (variable Object)
        , Unparse (variable level)
        , ShowMetaOrObject variable
        )
    => [BuiltinAndAxiomSimplifier level]
    -> AcceptsMultipleResults
    -> MetadataTools level StepperAttributes
    -> PredicateSubstitutionSimplifier level
    -> StepPatternSimplifier level
    -> BuiltinAndAxiomSimplifierMap level
    -- ^ Map from axiom IDs to axiom evaluators
    -> StepPattern level variable
    -> Simplifier
        (AttemptedAxiom level variable, SimplificationProof level)
applyFirstSimplifierThatWorks [] _ _ _ _ _ _ =
    return
        ( AttemptedAxiom.NotApplicable
        , SimplificationProof
        )
applyFirstSimplifierThatWorks
    (BuiltinAndAxiomSimplifier evaluator : evaluators)
    multipleResults
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    patt
  = do
    (applicationResult, _proof) <-
        evaluator
            tools substitutionSimplifier simplifier axiomIdToSimplifier patt

    case applicationResult of
        AttemptedAxiom.Applied AttemptedAxiomResults
            { results = orResults
            , remainders = orRemainders
            } -> do
                when
                    (length (MultiOr.extractPatterns orResults) > 1
                    && not (acceptsMultipleResults multipleResults)
                    )
                    -- We should only allow multiple simplification results
                    -- when they are created by unification splitting the
                    -- configuration.
                    -- However, right now, we shouldn't be able to get more
                    -- than one result, so we throw an error.
                    (error
                        (  "Unexpected simplification result with more "
                        ++ "than one configuration: "
                        ++ show applicationResult
                        )
                    )
                when
                    (not (OrOfExpandedPattern.isFalse orRemainders)
                    && not (acceptsMultipleResults multipleResults)
                    )
                    -- It's not obvious that we should accept simplifications
                    -- that change only a part of the configuration, since
                    -- that will probably make things more complicated.
                    --
                    -- Until we have a clear example that this can actually
                    -- happen, we throw an error.
                    ((error . unlines)
                        [ "Unexpected simplification result with remainder:"
                        , "  input: " ++ unparseToString patt
                        , "  result: " ++ show applicationResult
                        ]
                    )
                return (applicationResult, SimplificationProof)
        AttemptedAxiom.NotApplicable ->
            applyFirstSimplifierThatWorks
                evaluators
                multipleResults
                tools
                substitutionSimplifier
                simplifier
                axiomIdToSimplifier
                patt

evaluateWithDefinitionAxioms
    :: forall variable level
    .   ( FreshVariable variable
        , MetaOrObject level
        , Ord (variable level)
        , OrdMetaOrObject variable
        , SortedVariable variable
        , Show (variable level)
        , Show (variable Object)
        , Unparse (variable level)
        , ShowMetaOrObject variable
        )
    => [EqualityRule level Variable]
    -> MetadataTools level StepperAttributes
    -> PredicateSubstitutionSimplifier level
    -> StepPatternSimplifier level
    -> BuiltinAndAxiomSimplifierMap level
    -- ^ Map from axiom IDs to axiom evaluators
    -> StepPattern level variable
    -> Simplifier
        (AttemptedAxiom level variable, SimplificationProof level)
evaluateWithDefinitionAxioms
    definitionRules
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    patt
  = do
    let
        expanded :: ExpandedPattern level variable
        expanded = ExpandedPattern.fromPurePattern patt

    let unwrapEqualityRule =
            \(EqualityRule rule) ->
                RulePattern.mapVariables fromVariable rule
    resultOrError <- runExceptT
        $ stepWithRemaindersForUnifier
            tools
            (UnificationProcedure unificationWithAppMatchOnTop)
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            (map unwrapEqualityRule definitionRules)
            expanded

    let OrStepResult { rewrittenPattern, remainder } = case resultOrError of
            Right (result, _proof) -> result
            Left _ -> OrStepResult
                { rewrittenPattern = MultiOr.make []
                , remainder = MultiOr.make [expanded]
                }
    let
        remainderResults :: [ExpandedPattern level variable]
        remainderResults = MultiOr.extractPatterns remainder

        simplifyPredicate
            :: ExpandedPattern level variable
            -> Simplifier
                (ExpandedPattern level variable, SimplificationProof level)
        simplifyPredicate =
            ExpandedPattern.simplifyPredicate
                tools
                substitutionSimplifier
                simplifier
                axiomIdToSimplifier

    simplifiedRemainderList <- mapM simplifyPredicate remainderResults
    let
        simplifiedRemainderResults :: [ExpandedPattern level variable]
        (simplifiedRemainderResults, _proofs) =
            unzip simplifiedRemainderList
    return
        ( AttemptedAxiom.Applied AttemptedAxiomResults
            { results = rewrittenPattern
            , remainders = MultiOr.make simplifiedRemainderResults
            }
        , SimplificationProof
        )
