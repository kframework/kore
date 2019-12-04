{-|
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com

This should be imported qualified.
-}

module Kore.Strategies.Verification
    ( Claim
    , CommonProofState
    , verify
    , verifyClaimStep
    , toRulePattern
    ) where

import Control.Monad.Catch
    ( MonadCatch
    )
import Control.Monad.Except
    ( ExceptT
    )
import qualified Control.Monad.Except as Monad.Except
import qualified Control.Monad.Trans as Monad.Trans
import qualified Data.Foldable as Foldable
import qualified Data.Graph.Inductive.Graph as Graph
import Data.Limit
    ( Limit
    )
import qualified Data.Limit as Limit
import qualified Data.Stream.Infinite as Stream
import Data.Typeable
    ( Typeable
    )

import Kore.Debug
import Kore.Internal.Pattern
    ( Pattern
    )
import Kore.Step.Rule.Expand
import Kore.Step.Rule.Simplify
import Kore.Step.Simplification.Simplify
import Kore.Step.Strategy
import Kore.Step.Transition
    ( runTransitionT
    )
import qualified Kore.Step.Transition as Transition
import Kore.Strategies.Goal
import qualified Kore.Strategies.ProofState as ProofState
import Kore.Syntax.Variable
    ( Variable
    )
import Kore.Unparser
import Numeric.Natural
    ( Natural
    )

type CommonProofState  = ProofState.ProofState (Pattern Variable)

{- | Class type for claim-like rules
-}
type Claim claim =
    ( ToRulePattern claim
    , ToRulePattern (Rule claim)
    , FromRulePattern claim
    , FromRulePattern (Rule claim)
    , Unparse claim
    , Unparse (Rule claim)
    , Goal claim
    , ClaimExtractor claim
    , ExpandSingleConstructors claim
    , SimplifyRuleLHS claim
    , Typeable claim
    , Prim claim ~ ProofState.Prim (Rule claim)
    , ProofState claim claim ~ ProofState.ProofState claim
    )

{- | @Verifer a@ is a 'Simplifier'-based action which returns an @a@.

The action may throw an exception if the proof fails; the exception is a single
@'Pattern' 'Variable'@, the first unprovable configuration.

 -}
type Verifier m = ExceptT (Pattern Variable) m

{- | Verifies a set of claims. When it verifies a certain claim, after the
first step, it also uses the claims as axioms (i.e. it does coinductive proofs).

If the verification fails, returns an error containing a pattern that could
not be rewritten (either because no axiom could be applied or because we
didn't manage to verify a claim within the its maximum number of steps.

If the verification succeeds, it returns ().
-}

verify
    :: forall claim m
    .  Claim claim
    => ProofState claim (Pattern Variable) ~ CommonProofState
    => Show claim
    => (MonadCatch m, MonadSimplify m)
    => GraphSearchOrder
    -> [claim]
    -> [Rule claim]
    -> [(claim, Limit Natural)]
    -- ^ List of claims, together with a maximum number of verification steps
    -- for each.
    -> ExceptT (Pattern Variable) m ()
verify searchOrder claims axioms = mapM_ (verifyClaim searchOrder claims axioms)

verifyClaim
    :: forall claim m
    .  (MonadCatch m, MonadSimplify m)
    => ProofState claim (Pattern Variable) ~ CommonProofState
    => Claim claim
    => Show claim
    => GraphSearchOrder
    -> [claim]
    -> [Rule claim]
    -> (claim, Limit Natural)
    -> ExceptT (Pattern Variable) m ()
verifyClaim searchOrder claims axioms (goal, stepLimit) =
    traceExceptT D_OnePath_verifyClaim [debugArg "rule" goal] $ do
    let
        startPattern = ProofState.Goal $ getConfiguration goal
        destination = getDestination goal
        limitedStrategy =
            Limit.takeWithin
                stepLimit
                (Foldable.toList $ strategy goal claims axioms)
    executionGraph <-
        runStrategyWithSearchOrder
            (modifiedTransitionRule destination)
            limitedStrategy
            searchOrder
            startPattern
    -- Throw the first unproven configuration as an error.
    Foldable.traverse_ Monad.Except.throwError (unprovenNodes executionGraph)
  where
    modifiedTransitionRule
        :: Pattern Variable
        -> Prim claim
        -> CommonProofState
        -> TransitionT (Rule claim) (Verifier m) CommonProofState
    modifiedTransitionRule destination prim proofState' = do
        transitions <-
            Monad.Trans.lift . Monad.Trans.lift . runTransitionT
            $ transitionRule' goal destination prim proofState'
        Transition.scatter transitions

-- | Attempts to perform a single proof step, starting at the configuration
-- in the execution graph designated by the provided node. Re-constructs the
-- execution graph by inserting this step.
verifyClaimStep
    :: forall claim m
    .  (MonadCatch m, MonadSimplify m)
    => Claim claim
    => claim
    -- ^ claim that is being proven
    -> [claim]
    -- ^ list of claims in the spec module
    -> [Rule claim]
    -- ^ list of axioms in the main module
    -> ExecutionGraph CommonProofState (Rule claim)
    -- ^ current execution graph
    -> Graph.Node
    -- ^ selected node in the graph
    -> m (ExecutionGraph CommonProofState (Rule claim))
verifyClaimStep
    target
    claims
    axioms
    eg@ExecutionGraph { root }
    node
  = do
      let destination = getDestination target
      executionHistoryStep
        (transitionRule' target destination)
        strategy'
        eg
        node
  where
    strategy' :: Strategy (Prim claim)
    strategy'
        | isRoot = firstStep
        | otherwise = followupStep

    firstStep :: Strategy (Prim claim)
    firstStep = strategy target claims axioms Stream.!! 0

    followupStep :: Strategy (Prim claim)
    followupStep = strategy target claims axioms Stream.!! 1

    isRoot :: Bool
    isRoot = node == root

transitionRule'
    :: forall claim m
    .  (MonadCatch m, MonadSimplify m)
    => Claim claim
    => claim
    -> Pattern Variable
    -> Prim claim
    -> CommonProofState
    -> TransitionT (Rule claim) m CommonProofState
transitionRule' ruleType destination prim state = do
    let goal = flip (makeRuleFromPatterns ruleType) destination <$> state
    next <- transitionRule prim goal
    pure $ fmap getConfiguration next
