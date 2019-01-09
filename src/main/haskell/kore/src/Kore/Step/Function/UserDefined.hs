{-|
Module      : Kore.Step.Function.UserDefined
Description : Evaluates user-defined functions in a pattern.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Function.UserDefined
    ( StepPatternSimplifier
    , ruleFunctionEvaluator
    ) where

import Control.Monad.Except
       ( runExceptT )

import           Kore.AST.Pure
import           Kore.AST.Valid
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools (..) )
import           Kore.Predicate.Predicate
                 ( pattern PredicateFalse, makeTruePredicate )
import           Kore.Step.AxiomPatterns
                 ( EqualityRule (EqualityRule) )
import           Kore.Step.BaseStep
                 ( StepResult (StepResult), UnificationProcedure (..),
                 stepWithRuleForUnifier )
import           Kore.Step.BaseStep as StepResult
                 ( StepProof, StepResult (..) )
import           Kore.Step.ExpandedPattern
                 ( ExpandedPattern, Predicated (..) )
import           Kore.Step.Function.Data as AttemptedFunction
                 ( AttemptedFunction (..) )
import           Kore.Step.Function.Matcher
                 ( matchAsUnification )
import qualified Kore.Step.OrOfExpandedPattern as OrOfExpandedPattern
                 ( make )
import           Kore.Step.Pattern
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier, SimplificationProof (..),
                 Simplifier, StepPatternSimplifier (..) )
import qualified Kore.Step.Simplification.ExpandedPattern as ExpandedPattern
import           Kore.Step.StepperAttributes
                 ( StepperAttributes )
import           Kore.Unparser
import           Kore.Variables.Fresh

{-| 'ruleFunctionEvaluator' evaluates a user-defined function. After
evaluating the function, it tries to re-evaluate all functions on the result.

The function is assumed to be defined through an axiom.
-}
ruleFunctionEvaluator
    ::  forall level variable.
        ( FreshVariable variable
        , SortedVariable variable
        , MetaOrObject level
        , Ord (variable level)
        , Show (variable level)
        , Unparse (variable level)
        , OrdMetaOrObject variable
        , ShowMetaOrObject variable
        )
    => EqualityRule level
    -- ^ Axiom defining the current function.
    -> MetadataTools level StepperAttributes
    -- ^ Tools for finding additional information about patterns
    -- such as their sorts, whether they are constructors or hooked.
    -> PredicateSubstitutionSimplifier level Simplifier
    -> StepPatternSimplifier level variable
    -- ^ Evaluates functions in patterns
    -> CofreeF
        (Application level)
        (Valid level)
        (StepPattern level variable)
    -- ^ The function on which to evaluate the current function.
    -> Simplifier
        [(AttemptedFunction level variable, SimplificationProof level)]
ruleFunctionEvaluator
    (EqualityRule rule)
    tools
    substitutionSimplifier
    simplifier
    app
  = do
    result <- runExceptT stepResult
    case result of
        Left _ ->
            return [(AttemptedFunction.NotApplicable, SimplificationProof)]
        Right results -> do
            processedResults <- mapM processResult results
            return (concat processedResults)
  where
    stepResult =
        stepWithRuleForUnifier
            tools
            (UnificationProcedure matchAsUnification)
            substitutionSimplifier
            (stepperConfiguration app)
            rule

    stepperConfiguration
        :: MetaOrObject level
        => CofreeF
            (Application level)
            (Valid level)
            (StepPattern level variable)
        -> ExpandedPattern level variable
    stepperConfiguration (valid :< app') =
        Predicated
            { term = asPurePattern (valid :< ApplicationPattern app')
            , predicate = makeTruePredicate
            , substitution = mempty
            }
    processResult
        :: (StepResult level variable, StepProof level variable)
        -> Simplifier
            [(AttemptedFunction level variable, SimplificationProof level)]
    processResult
        (StepResult { rewrittenPattern = stepPattern }, _proof)
        -- TODO(virgil): ^^^ Also use the remainder.
      = do
        (   rewrittenPattern@Predicated
                { predicate = rewritingCondition }
            , _
            ) <-
                ExpandedPattern.simplifyPredicate
                    tools substitutionSimplifier simplifier stepPattern
        let
            results =
                case rewritingCondition of
                    PredicateFalse -> []
                    _ -> [rewrittenPattern]
        return
            [   ( AttemptedFunction.Applied
                    (OrOfExpandedPattern.make results)
                , SimplificationProof
                )
            ]
