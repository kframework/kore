{-|
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com

This should be imported qualified.
-}

module Kore.Reachability.Prove
    ( CommonClaimState
    , ProveClaimsResult (..)
    , StuckClaim (..)
    , StuckClaims
    , AllClaims (..)
    , Axioms (..)
    , ToProve (..)
    , AlreadyProven (..)
    , proveClaims
    , proveClaimStep
    , lhsClaimStateTransformer
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( deepseq
    )
import qualified Control.Lens as Lens
import Control.Monad
    ( (>=>)
    )
import Control.Monad.Catch
    ( MonadCatch
    , MonadMask
    , handle
    , handleAll
    , throwM
    )
import Control.Monad.Except
    ( ExceptT
    , MonadError
    , runExceptT
    )
import qualified Control.Monad.Except as Monad.Except
import Control.Monad.State.Strict
    ( StateT
    , runStateT
    )
import qualified Control.Monad.State.Strict as State
import Data.Coerce
    ( coerce
    )
import qualified Data.Graph.Inductive.Graph as Graph
import Data.List.Extra
    ( groupSortOn
    )
import Data.Text
    ( Text
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC
import Numeric.Natural
    ( Natural
    )

import Data.Limit
    ( Limit
    )
import qualified Data.Limit as Limit
import qualified Kore.Attribute.Axiom as Attribute.Axiom
import Kore.Debug
import Kore.Internal.Conditional
    ( Conditional (..)
    )
import Kore.Internal.MultiAnd
    ( MultiAnd
    )
import qualified Kore.Internal.MultiAnd as MultiAnd
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( getMultiAndPredicate
    , unwrapPredicate
    )
import Kore.Internal.TermLike
    ( pattern Ceil_
    , pattern Not_
    , TermLike (..)
    )
import Kore.Log.DebugClaimState
import Kore.Log.DebugProven
import Kore.Log.InfoExecBreadth
import Kore.Log.InfoProofDepth
import Kore.Log.WarnTrivialClaim
import Kore.Reachability.Claim
import Kore.Reachability.ClaimState
    ( ClaimState
    , ClaimStateTransformer (..)
    , extractStuck
    , extractUnproven
    )
import qualified Kore.Reachability.ClaimState as ClaimState
import qualified Kore.Reachability.Prim as Prim
    ( Prim (..)
    )
import Kore.Reachability.SomeClaim
import Kore.Rewriting.RewritingVariable
    ( RewritingVariableName
    , getRewritingPattern
    )
import Kore.Step.ClaimPattern
    ( mkGoal
    )
import Kore.Step.Simplification.Simplify
import Kore.Step.Strategy
    ( ExecutionGraph (..)
    , GraphSearchOrder
    , Strategy
    , executionHistoryStep
    )
import qualified Kore.Step.Strategy as Strategy
import Kore.Step.Transition
    ( runTransitionT
    )
import qualified Kore.Step.Transition as Transition
import Kore.TopBottom
import Kore.Unparser
import Log
    ( MonadLog (..)
    )
import Logic
    ( LogicT
    )
import qualified Logic
import qualified Pretty
import Prof

type CommonClaimState = ClaimState.ClaimState SomeClaim

type CommonTransitionRule m =
    TransitionRule m (AppliedRule SomeClaim) CommonClaimState

-- | Extracts the left hand side (configuration) from the
-- 'CommonClaimState'. If the 'ClaimState' is 'Proven', then
-- the configuration will be '\\bottom'.
lhsClaimStateTransformer
    :: ClaimStateTransformer
        SomeClaim
        (Pattern RewritingVariableName)
lhsClaimStateTransformer =
    ClaimStateTransformer
        { claimedTransformer = getConfiguration
        , remainingTransformer = getConfiguration
        , rewrittenTransformer = getConfiguration
        , stuckTransformer = getConfiguration
        , provenValue = Pattern.bottom
        }

{- | @Verifer a@ is a 'Simplifier'-based action which returns an @a@.

The action may throw an exception if the proof fails; the exception is a single
@'Pattern' 'VariableName'@, the first unprovable configuration.

 -}
type VerifierT = ExceptT StuckClaims

newtype AllClaims claim = AllClaims {getAllClaims :: [claim]}
newtype Axioms claim = Axioms {getAxioms :: [Rule claim]}
newtype ToProve claim = ToProve {getToProve :: [(claim, Limit Natural)]}
newtype AlreadyProven = AlreadyProven {getAlreadyProven :: [Text]}

newtype StuckClaim = StuckClaim { getStuckClaim :: SomeClaim }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance TopBottom StuckClaim where
    isTop = const False
    isBottom = const False

type StuckClaims = MultiAnd StuckClaim

type ProvenClaims = MultiAnd SomeClaim

-- | The result of proving some claims.
data ProveClaimsResult =
    ProveClaimsResult
    { stuckClaims :: !StuckClaims
    -- ^ The conjuction of stuck claims, that is: of claims which must still be
    -- proven. If all claims were proved, then the remaining claims are @\\top@.
    , provenClaims :: !ProvenClaims
    -- ^ The conjunction of all claims which were proven.
    }

proveClaims
    :: forall simplifier
    .  MonadMask simplifier
    => MonadSimplify simplifier
    => MonadProf simplifier
    => Limit Natural
    -> GraphSearchOrder
    -> AllClaims SomeClaim
    -> Axioms SomeClaim
    -> AlreadyProven
    -> ToProve SomeClaim
    -- ^ List of claims, together with a maximum number of verification steps
    -- for each.
    -> simplifier ProveClaimsResult
proveClaims
    breadthLimit
    searchOrder
    claims
    axioms
    (AlreadyProven alreadyProven)
    (ToProve toProve)
  = do
    (result, provenClaims) <-
        proveClaimsWorker breadthLimit searchOrder claims axioms unproven
        & runExceptT
        & flip runStateT (MultiAnd.make stillProven)
    pure ProveClaimsResult
        { stuckClaims = either id (const MultiAnd.top) result
        , provenClaims
        }
  where
    unproven :: ToProve SomeClaim
    stillProven :: [SomeClaim]
    (unproven, stillProven) =
        (ToProve newToProve, newAlreadyProven)
      where
        (newToProve, newAlreadyProven) =
            partitionEithers (map lookupEither toProve)
        lookupEither
            :: (SomeClaim, Limit Natural)
            -> Either (SomeClaim, Limit Natural) SomeClaim
        lookupEither claim@(rule, _) =
            if unparseToText2 rule `elem` alreadyProven
                then Right rule
                else Left claim

proveClaimsWorker
    :: forall simplifier
    .  MonadSimplify simplifier
    => MonadMask simplifier
    => MonadProf simplifier
    => Limit Natural
    -> GraphSearchOrder
    -> AllClaims SomeClaim
    -> Axioms SomeClaim
    -> ToProve SomeClaim
    -- ^ List of claims, together with a maximum number of verification steps
    -- for each.
    -> ExceptT StuckClaims (StateT ProvenClaims simplifier) ()
proveClaimsWorker breadthLimit searchOrder claims axioms (ToProve toProve) =
    traverse_ verifyWorker toProve
  where
    verifyWorker
        :: (SomeClaim, Limit Natural)
        -> ExceptT StuckClaims (StateT ProvenClaims simplifier) ()
    verifyWorker unprovenClaim@(claim, _) = do
        proveClaim breadthLimit searchOrder claims axioms unprovenClaim
        addProvenClaim claim

    addProvenClaim claim =
        State.modify' (mappend (MultiAnd.singleton claim))

proveClaim
    :: forall simplifier
    .  MonadSimplify simplifier
    => MonadMask simplifier
    => MonadProf simplifier
    => Limit Natural
    -> GraphSearchOrder
    -> AllClaims SomeClaim
    -> Axioms SomeClaim
    -> (SomeClaim, Limit Natural)
    -> ExceptT StuckClaims simplifier ()
proveClaim
    breadthLimit
    searchOrder
    (AllClaims claims)
    (Axioms axioms)
    (goal, depthLimit)
  =
    traceExceptT D_OnePath_verifyClaim [debugArg "rule" goal] $ do
    let
        startGoal = ClaimState.Claimed (Lens.over lensClaimPattern mkGoal goal)
        limitedStrategy =
            strategy
            & toList
            & Limit.takeWithin depthLimit
    proofDepths <-
        Strategy.leavesM
            updateQueue
            (Strategy.unfoldTransition transit)
            (limitedStrategy, (ProofDepth 0, startGoal))
            & fmap discardStrategy
            & throwUnproven
            & handle handleLimitExceeded
    let maxProofDepth = sconcat (ProofDepth 0 :| proofDepths)
    infoProvenDepth maxProofDepth
    warnProvenClaimZeroDepth maxProofDepth goal
  where
    discardStrategy = snd

    handleLimitExceeded
        :: Strategy.LimitExceeded (ProofDepth, CommonClaimState)
        -> VerifierT simplifier a
    handleLimitExceeded (Strategy.LimitExceeded states) = do
        let extractStuckClaim = fmap StuckClaim . extractUnproven . snd
            stuckClaims = mapMaybe extractStuckClaim states
        Monad.Except.throwError (MultiAnd.make $ toList stuckClaims)

    updateQueue = \as ->
        Strategy.unfoldSearchOrder searchOrder as
        >=> lift . Strategy.applyBreadthLimit breadthLimit discardStrategy
        >=> ( \queue ->
                infoExecBreadth (ExecBreadth $ genericLength queue)
                >> return queue
            )
      where
        genericLength = fromIntegral . length

    throwUnproven
        :: LogicT (VerifierT simplifier) (ProofDepth, CommonClaimState)
        -> VerifierT simplifier [ProofDepth]
    throwUnproven acts =
        do
            (proofDepth, proofState) <- acts
            let maybeUnproven = extractUnproven proofState
            for_ maybeUnproven $ \unproven -> do
                infoUnprovenDepth proofDepth
                throwStuckClaim unproven
            pure proofDepth
        & Logic.observeAllT

    discardAppliedRules = map fst

    transit instr config =
        Strategy.transitionRule
            (transitionRule' claims axioms
                & trackProofDepth
                & throwStuckClaims
            )
            instr
            config
        & runTransitionT
        & fmap discardAppliedRules
        & traceProf ":transit"
        & lift

-- | Attempts to perform a single proof step, starting at the configuration
-- in the execution graph designated by the provided node. Re-constructs the
-- execution graph by inserting this step.
proveClaimStep
    :: forall simplifier
    .  MonadSimplify simplifier
    => MonadMask simplifier
    => MonadProf simplifier
    => [SomeClaim]
    -- ^ list of claims in the spec module
    -> [Rule SomeClaim]
    -- ^ list of axioms in the main module
    -> ExecutionGraph CommonClaimState (AppliedRule SomeClaim)
    -- ^ current execution graph
    -> Graph.Node
    -- ^ selected node in the graph
    -> simplifier (ExecutionGraph CommonClaimState (AppliedRule SomeClaim))
proveClaimStep claims axioms executionGraph node =
    executionHistoryStep
        transitionRule''
        strategy'
        executionGraph
        node
  where
    strategy' :: Strategy Prim
    strategy'
        | isRoot = firstStep
        | otherwise = followupStep

    firstStep :: Strategy Prim
    firstStep = reachabilityFirstStep

    followupStep :: Strategy Prim
    followupStep = reachabilityNextStep

    ExecutionGraph { root } = executionGraph

    isRoot :: Bool
    isRoot = node == root

    transitionRule'' prim state
        | isRoot =
            transitionRule'
                claims
                axioms
                prim
                (Lens.over lensClaimPattern mkGoal <$> state)
        | otherwise =
            transitionRule' claims axioms prim state

transitionRule'
    :: MonadSimplify simplifier
    => MonadProf simplifier
    => MonadMask simplifier
    => [SomeClaim]
    -> [Rule SomeClaim]
    -> CommonTransitionRule simplifier
transitionRule' claims axioms = \prim proofState ->
    deepseq proofState
        (transitionRule claims axiomGroups
            & profTransitionRule
            & withConfiguration
            & withDebugClaimState
            & withDebugProven
            & logTransitionRule
            & checkStuckConfiguration
        )
        prim proofState
  where
    axiomGroups = groupSortOn Attribute.Axiom.getPriorityOfAxiom axioms

profTransitionRule
    :: forall m
    .  MonadProf m
    => CommonTransitionRule m
    -> CommonTransitionRule m
profTransitionRule rule prim proofState =
    case prim of
        Prim.ApplyClaims -> tracing ":transit:apply-claims"
        Prim.ApplyAxioms -> tracing ":transit:apply-axioms"
        Prim.CheckImplication -> tracing ":transit:check-implies"
        Prim.Simplify -> tracing ":transit:simplify"
        _ -> rule prim proofState
  where
    tracing name =
        lift (traceProf name (runTransitionT (rule prim proofState)))
        >>= Transition.scatter

logTransitionRule
    :: forall m
    .  MonadSimplify m
    => CommonTransitionRule m
    -> CommonTransitionRule m
logTransitionRule rule prim proofState =
    whileReachability prim $ rule prim proofState

checkStuckConfiguration
    :: CommonTransitionRule m
    -> CommonTransitionRule m
checkStuckConfiguration rule prim proofState = do
    proofState' <- rule prim proofState
    for_ (extractStuck proofState) $ \rule' -> do
        let resultPatternPredicate = predicate (getConfiguration rule')
            multiAndPredicate = getMultiAndPredicate resultPatternPredicate
        when (any (isNot_Ceil_ . unwrapPredicate) multiAndPredicate) $
            error . show . Pretty.vsep $
                [ "Found '\\not(\\ceil(_))' in stuck configuration:"
                , Pretty.pretty rule'
                , "Please file a bug report:\
                  \ https://github.com/kframework/kore/issues"
                ]
    return proofState'
  where
    isNot_Ceil_ :: TermLike variable -> Bool
    isNot_Ceil_ (Not_ _ (Ceil_ _ _ _)) = True
    isNot_Ceil_ _ = False

throwStuckClaim :: MonadError StuckClaims m => SomeClaim -> m x
throwStuckClaim = Monad.Except.throwError . MultiAnd.singleton . StuckClaim

{- | Terminate the prover at the first stuck step.
 -}
throwStuckClaims
    ::  forall m rule
    .   MonadLog m
    =>  TransitionRule (VerifierT m) rule
            (ProofDepth, ClaimState SomeClaim)
    ->  TransitionRule (VerifierT m) rule
            (ProofDepth, ClaimState SomeClaim)
throwStuckClaims rule prim state = do
    state'@(proofDepth', proofState') <- rule prim state
    case proofState' of
        ClaimState.Stuck unproven -> do
            infoUnprovenDepth proofDepth'
            throwStuckClaim unproven
        _ -> return state'

{- | Modify a 'TransitionRule' to track the depth of a proof.
 -}
trackProofDepth
    :: forall m rule goal
    .  TransitionRule m rule (ClaimState goal)
    -> TransitionRule m rule (ProofDepth, ClaimState goal)
trackProofDepth rule prim (!proofDepth, proofState) = do
    proofState' <- rule prim proofState
    let proofDepth' = (if didRewrite proofState' then succ else id) proofDepth
    pure (proofDepth', proofState')
  where
    didRewrite proofState' =
        isApply prim
        && ClaimState.isRewritable proofState
        && isRewritten proofState'

    isApply Prim.ApplyClaims = True
    isApply Prim.ApplyAxioms = True
    isApply _                = False

    isRewritten (ClaimState.Rewritten _) = True
    isRewritten  ClaimState.Proven       = True
    isRewritten _                        = False

debugClaimStateBracket
    :: forall monad
    .  MonadLog monad
    => ClaimState SomeClaim
    -- ^ current proof state
    -> Prim
    -- ^ transition
    -> monad (ClaimState SomeClaim)
    -- ^ action to be computed
    -> monad (ClaimState SomeClaim)
debugClaimStateBracket
    proofState
    (coerce -> transition)
    action
  = do
    result <- action
    logEntry DebugClaimState
        { proofState
        , transition
        , result = Just result
        }
    return result

debugClaimStateFinal
    :: forall monad
    .  Alternative monad
    => MonadLog monad
    => ClaimState SomeClaim
    -- ^ current proof state
    -> Prim
    -- ^ transition
    -> monad (ClaimState SomeClaim)
debugClaimStateFinal proofState (coerce -> transition) = do
    logEntry DebugClaimState
        { proofState
        , transition
        , result = Nothing
        }
    empty

withDebugClaimState
    :: forall monad
    .  MonadLog monad
    => CommonTransitionRule monad
    -> CommonTransitionRule monad
withDebugClaimState transitionFunc =
    \transition state ->
        Transition.orElse
            (debugClaimStateBracket
                state
                transition
                (transitionFunc transition state)
            )
            (debugClaimStateFinal
                state
                transition
            )

withDebugProven
    :: forall monad
    .  MonadLog monad
    => CommonTransitionRule monad
    -> CommonTransitionRule monad
withDebugProven rule prim state =
    rule prim state >>= debugProven
  where
    debugProven state'
      | ClaimState.Proven <- state'
      , Just claim <- extractUnproven state
      = do
        Log.logEntry DebugProven { claim }
        pure state'
      | otherwise = pure state'

withConfiguration
    :: MonadCatch monad
    => CommonTransitionRule monad
    -> CommonTransitionRule monad
withConfiguration transit prim proofState =
    handle' (transit prim proofState)
  where
    config = extractUnproven proofState & fmap getConfiguration
    handle' = maybe id handleConfig config
    handleConfig config' =
        handleAll
        $ throwM
        . WithConfiguration (getRewritingPattern config')
