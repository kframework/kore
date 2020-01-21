{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}
module Kore.Step.Simplification.OrPattern
    ( simplifyConditionsWithSmt
    ) where

import qualified Control.Monad.Trans as Monad.Trans

import qualified Branch as BranchT
import Kore.Internal.Condition
    ( Condition
    )
import qualified Kore.Internal.Condition as Condition
    ( bottom
    , fromPredicate
    , toPredicate
    , top
    )
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional
    ( Conditional (..)
    )
import qualified Kore.Internal.MultiOr as MultiOr
import Kore.Internal.OrCondition
    ( OrCondition
    )
import qualified Kore.Internal.OrCondition as OrCondition
    ( fromConditions
    )
import Kore.Internal.OrPattern
    ( OrPattern
    )
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
    ( splitTerm
    , withCondition
    )
import Kore.Internal.Predicate
    ( makeAndPredicate
    , makeNotPredicate
    )
import Kore.Internal.SideCondition
    ( SideCondition
    )
import qualified Kore.Internal.SideCondition as SideCondition
    ( toPredicate
    , top
    )
import Kore.Step.Simplification.Simplify
    ( MonadSimplify
    , SimplifierVariable
    , simplifyCondition
    )
import qualified Kore.Step.SMT.Evaluator as SMT.Evaluator
    ( filterMultiOr
    )
import Kore.TopBottom
    ( TopBottom (..)
    )

simplifyConditionsWithSmt
    ::  forall variable simplifier
    .   (MonadSimplify simplifier, SimplifierVariable variable)
    => SideCondition variable
    -> OrPattern variable
    -> simplifier (OrPattern variable)
simplifyConditionsWithSmt sideCondition unsimplified =
    fmap MultiOr.mergeAll . BranchT.gather $ do
        unsimplified1 <- BranchT.scatter unsimplified
        Monad.Trans.lift $ simplifyAndPrune unsimplified1
  where
    simplifyAndPrune
        :: Pattern variable -> simplifier (OrPattern variable)
    simplifyAndPrune (Pattern.splitTerm -> (term, condition)) =
        fmap orPatternFromConditions . BranchT.gather $ do
            simplified <- simplifyCondition sideCondition condition

            Monad.Trans.lift $ resultWithFilter
                rejectCondition
                (resultWithFilter pruneCondition (return simplified))
      where
        addTerm :: OrCondition variable -> OrPattern variable
        addTerm = fmap (Pattern.withCondition term)

        orPatternFromConditions :: [Condition variable] -> OrPattern variable
        orPatternFromConditions = addTerm . OrCondition.fromConditions

    resultWithFilter
        :: (Condition variable -> simplifier (Maybe Bool))
        -> simplifier (Condition variable)
        -> simplifier (Condition variable)
    resultWithFilter conditionFilter previousResult = do
        previous <- previousResult
        if isTop previous || isBottom previous
            then return previous
            else do
                filtered <- conditionFilter previous
                case filtered of
                    Just True -> return Condition.top
                    Just False -> return Condition.bottom
                    Nothing -> return previous

    {- | Check if the side condition implies the argument. If so, then
    returns @Just True@. If the side condition never implies the argument,
    returns False. Otherwise, returns Nothing.

    Note that the SMT evaluators currently only allow us to detect the
    @Just True@ branch.

    The side condition implies the argument, i.e. @side → arg@, iff
    @¬side ∨ arg@ iff @not(side ∧ ¬arg)@.

    In other words:

    @side ∧ ¬arg@ is not satisfiable iff @side → arg@ is @⊤@.
    @side ∧ ¬arg@ is always true iff @side → arg@ is @⊤@
    -}
    pruneCondition :: Condition variable -> simplifier (Maybe Bool)
    pruneCondition condition = do
        implicationNegation <-
            fmap OrCondition.fromConditions . BranchT.gather
            $ simplifyCondition
                SideCondition.top
                (Condition.fromPredicate
                    (makeAndPredicate
                        sidePredicate
                        (makeNotPredicate $ Condition.toPredicate condition)
                    )
                )
        filteredConditions <- SMT.Evaluator.filterMultiOr implicationNegation
        if isTop filteredConditions
            then return (Just False)
            else if isBottom filteredConditions
                then return (Just True)
                else return Nothing

    rejectCondition :: Condition variable -> simplifier (Maybe Bool)
    rejectCondition condition = do
        simplifiedConditions <-
            fmap OrCondition.fromConditions . BranchT.gather
            $ simplifyCondition
                    SideCondition.top
                    (addPredicate condition)
        filteredConditions <- SMT.Evaluator.filterMultiOr simplifiedConditions
        if isBottom filteredConditions
            then return (Just False)
            else if isTop filteredConditions
                then return (Just True)
                else return Nothing


    sidePredicate = SideCondition.toPredicate sideCondition

    addPredicate :: Conditional variable term -> Conditional variable term
    addPredicate c@Conditional {predicate} =
        c {Conditional.predicate = makeAndPredicate predicate sidePredicate}
