{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}
module Kore.AllPath where

import           Control.Applicative
                 ( Alternative (..) )
import qualified Data.Foldable as Foldable
import           Data.Maybe
                 ( mapMaybe )

import qualified Kore.Internal.MultiOr as MultiOr
import           Kore.Step.Strategy
                 ( Strategy )
import qualified Kore.Step.Strategy as Strategy

{- | The state of the all-path reachability proof strategy for @goal@.
 -}
data ProofState goal
    = Goal goal
    -- ^ The indicated goal is being proven.
    | GoalRem goal
    -- ^ The indicated goal remains after rewriting.
    | Proven
    -- ^ The parent goal was proven.
    deriving (Eq, Show)

{- | Extract the unproven goals of a 'ProofState'.

Returns 'Nothing' if there is no remaining unproven goal.

 -}
extractUnproven :: ProofState goal -> Maybe goal
extractUnproven (Goal t)    = Just t
extractUnproven (GoalRem t) = Just t
extractUnproven Proven      = Nothing

{- | The final nodes of an execution graph which were not proven.

See also: 'Strategy.pickFinal', 'extractUnproven'

 -}
unprovenNodes
    :: Strategy.ExecutionGraph (ProofState goal) rule
    -> MultiOr.MultiOr goal
unprovenNodes executionGraph =
    MultiOr.MultiOr
    $ mapMaybe extractUnproven
    $ Strategy.pickFinal executionGraph

{- | Does the 'Strategy.ExecutionGraph' indicate a successful proof?
 -}
proven :: Strategy.ExecutionGraph (ProofState goal) rule -> Bool
proven = Foldable.null . unprovenNodes

{- | The primitive transitions of the all-path reachability proof strategy.
 -}
data Prim rule
    = CheckProven
    -- ^ End execution on this branch if the state is 'Proven'.
    | CheckGoalRem
    -- ^ End execution on this branch if the state is 'GoalRem'.
    | RemoveDestination
    | TriviallyValid
    | DerivePar [rule]

transitionRule
    :: Monad m
    => (goal -> Strategy.TransitionT rule m goal)
    -- ^ Remove destination from goal
    -> (goal -> Bool)
    -- ^ Check if the goal is trivially valid
    -> ([rule] -> goal -> Strategy.TransitionT rule m (ProofState goal))
    -- ^ Apply rules in parallel
    -> Prim rule
    -> ProofState goal
    -> Strategy.TransitionT rule m (ProofState goal)
transitionRule removeDestination triviallyValid derivePar = transitionRuleWorker
  where
    transitionRuleWorker CheckProven Proven = empty
    transitionRuleWorker CheckGoalRem (GoalRem _) = empty

    transitionRuleWorker RemoveDestination (Goal g) =
        GoalRem <$> removeDestination g

    transitionRuleWorker TriviallyValid (GoalRem g)
      | triviallyValid g = return Proven

    transitionRuleWorker (DerivePar rules) (GoalRem g) =
        derivePar rules g

    transitionRuleWorker _ state = return state

strategy
    :: [rule]
    -- ^ Claims
    -> [rule]
    -- ^ Axioms
    -> [Strategy (Prim rule)]
strategy claims axioms =
    firstStep : repeat nextStep
  where
    firstStep =
        (Strategy.sequence . map Strategy.apply)
            [ CheckProven
            , CheckGoalRem
            , RemoveDestination
            , TriviallyValid
            , DerivePar axioms
            , TriviallyValid
            ]
    nextStep =
        (Strategy.sequence . map Strategy.apply)
            [ CheckProven
            , CheckGoalRem
            , RemoveDestination
            , TriviallyValid
            , DerivePar claims
            , DerivePar axioms
            , TriviallyValid
            ]
