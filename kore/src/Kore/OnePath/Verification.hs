{-|
Module      : Kore.OnePath.Verification
Description : One-path verification
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com

This should be imported qualified.
-}

module Kore.OnePath.Verification
    ( Axiom (..)
    , Claim
    , isTrusted
    , defaultStrategy
    , verify
    , verifyClaimStep
    ) where

import           Control.Monad.Except
                 ( ExceptT )
import qualified Control.Monad.Except as Monad.Except
import qualified Control.Monad.Trans as Monad.Trans
import           Data.Coerce
                 ( Coercible, coerce )
import qualified Data.Foldable as Foldable
import qualified Data.Graph.Inductive.Graph as Graph
import           Data.Limit
                 ( Limit )
import qualified Data.Limit as Limit
import           Data.Maybe

import qualified Kore.Attribute.Axiom as Attribute
import qualified Kore.Attribute.Trusted as Trusted
import           Kore.Debug
import qualified Kore.Internal.MultiOr as MultiOr
import           Kore.Internal.Pattern
                 ( Conditional (Conditional), Pattern )
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.Pattern as Conditional
                 ( Conditional (..) )
import           Kore.OnePath.Step
                 ( Prim, onePathFirstStep, onePathFollowupStep )
import qualified Kore.OnePath.Step as OnePath
                 ( transitionRule )
import           Kore.OnePath.StrategyPattern
                 ( CommonStrategyPattern )
import qualified Kore.OnePath.StrategyPattern as StrategyPattern
import           Kore.Step.Rule
                 ( RewriteRule (RewriteRule), RulePattern (RulePattern) )
import           Kore.Step.Rule as RulePattern
                 ( RulePattern (..) )
import           Kore.Step.Simplification.Data
import           Kore.Step.Strategy
import           Kore.Step.Transition
                 ( runTransitionT )
import qualified Kore.Step.Transition as Transition
import           Kore.Syntax.Variable
                 ( Variable )
import           Kore.Unparser
import           Numeric.Natural
                 ( Natural )

{- NOTE: Non-deterministic semantics

The current implementation of one-path verification assumes that the proof goal
is deterministic, that is: the proof goal would not be discharged during at a
non-confluent state in the execution of a non-deterministic semantics. (Often
this means that the definition is simply deterministic.) As a result, given the
non-deterministic definition

> module ABC
>   import DOMAINS
>   syntax S ::= "a" | "b" | "c"
>   rule [ab]: a => b
>   rule [ac]: a => c
> endmodule

this claim would be provable,

> rule a => b [claim]

but this claim would **not** be provable,

> rule a => c [claim]

because the algorithm would first apply semantic rule [ab], which prevents rule
[ac] from being used.

We decided to assume that the definition is deterministic because one-path
verification is mainly used only for deterministic semantics and the assumption
simplifies the implementation. However, this assumption is not an essential
feature of the algorithm. You should not rely on this assumption elsewhere. This
decision is subject to change without notice.

 -}

{- | Class type for claim-like rules
-}
type Claim claim =
    ( Coercible (RulePattern Variable) claim
    , Coercible claim (RulePattern Variable)
    , Unparse claim
    )

-- | Is the 'Claim' trusted?
isTrusted :: Claim claim => claim -> Bool
isTrusted =
    Trusted.isTrusted
    . Attribute.trusted
    . RulePattern.attributes
    . coerce

{- | Wrapper for a rewrite rule that should be used as an axiom.
-}
newtype Axiom = Axiom
    { unAxiom :: RewriteRule Variable
    }

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
    :: MonadSimplify m
    =>  (  Pattern Variable
        -> [Strategy
            (Prim
                (Pattern Variable)
                (RewriteRule Variable)
            )
           ]
        )
    -- ^ Creates a one-step strategy from a target pattern. See
    -- 'defaultStrategy'.
    -> [(RewriteRule Variable, Limit Natural)]
    -- ^ List of claims, together with a maximum number of verification steps
    -- for each.
    -> ExceptT (Pattern Variable) m ()
verify strategyBuilder =
    mapM_ (verifyClaim strategyBuilder)

{- | Default implementation for a one-path strategy. You can apply it to the
first two arguments and pass the resulting function to 'verify'.

Things to note when implementing your own:

1. The first step does not use the reachability claims

2. You can return an infinite list.
-}
defaultStrategy
    :: forall claim
    .  Claim claim
    => [claim]
    -- The claims that we want to prove
    -> [Axiom]
    -> Pattern Variable
    -> [Strategy
        (Prim
            (Pattern Variable)
            (RewriteRule Variable)
        )
       ]
defaultStrategy
    claims
    axioms
    target
  =
    onePathFirstStep target rewrites
    : repeat
        (onePathFollowupStep
            target
            coinductiveRewrites
            rewrites
        )
  where
    rewrites :: [RewriteRule Variable]
    rewrites = map unwrap axioms
      where
        unwrap (Axiom a) = a
    coinductiveRewrites :: [RewriteRule Variable]
    coinductiveRewrites = map (RewriteRule . coerce) claims

verifyClaim
    :: forall m
    .  MonadSimplify m
    =>  (  Pattern Variable
        -> [Strategy (Prim (Pattern Variable) (RewriteRule Variable))]
        )
    -> (RewriteRule Variable, Limit Natural)
    -> ExceptT (Pattern Variable) m ()
verifyClaim
    strategyBuilder
    (rule@(RewriteRule RulePattern {left, right, requires, ensures}), stepLimit)
  = traceExceptT D_OnePath_verifyClaim [debugArg "rule" rule] $ do
    let
        strategy =
            Limit.takeWithin
                stepLimit
                (strategyBuilder
                    Conditional
                    { term = right
                    , predicate = ensures
                    , substitution = mempty
                    }
                )
        startPattern :: CommonStrategyPattern
        startPattern =
            StrategyPattern.RewritePattern
                Conditional
                    {term = left, predicate = requires, substitution = mempty}
    executionGraph <- runStrategy transitionRule' strategy startPattern
    -- Throw the first unproven configuration as an error.
    -- This might appear to be unnecessary because transitionRule' (below)
    -- throws an error if it encounters a Stuck proof state. However, the proof
    -- could also fail because the depth limit was reached, yet we never
    -- encountered a Stuck state.
    Foldable.traverse_ Monad.Except.throwError (unprovenNodes executionGraph)
  where
    transitionRule'
        :: Prim (Pattern Variable) (RewriteRule Variable)
        -> CommonStrategyPattern
        -> TransitionT (RewriteRule Variable) (Verifier m) CommonStrategyPattern
    transitionRule' prim proofState = do
        transitions <-
            Monad.Trans.lift . Monad.Trans.lift . runTransitionT
            $ OnePath.transitionRule prim proofState
        let (configs, _) = unzip transitions
            stuckConfigs = mapMaybe StrategyPattern.extractStuck configs
        Foldable.traverse_ Monad.Except.throwError stuckConfigs
        Transition.scatter transitions

-- | Find all final nodes of the execution graph that did not reach the goal
unprovenNodes
    :: ExecutionGraph (StrategyPattern.StrategyPattern term) rule
    -> MultiOr.MultiOr term
unprovenNodes executionGraph =
    MultiOr.MultiOr
    $ mapMaybe StrategyPattern.extractUnproven
    $ pickFinal executionGraph

-- | Attempts to perform a single proof step, starting at the configuration
-- in the execution graph designated by the provided node. Re-constructs the
-- execution graph by inserting this step.
verifyClaimStep
    :: forall claim m
    .  Claim claim
    => MonadSimplify m
    => claim
    -- ^ claim that is being proven
    -> [claim]
    -- ^ list of claims in the spec module
    -> [Axiom]
    -- ^ list of axioms in the main module
    -> ExecutionGraph CommonStrategyPattern (RewriteRule Variable)
    -- ^ current execution graph
    -> Graph.Node
    -- ^ selected node in the graph
    -> m (ExecutionGraph CommonStrategyPattern (RewriteRule Variable))
verifyClaimStep
    target
    claims
    axioms
    eg@ExecutionGraph { root }
    node
  = executionHistoryStep
        transitionRule'
        strategy'
        eg
        node
  where
    transitionRule'
        :: Prim (Pattern Variable) (RewriteRule Variable)
        -> CommonStrategyPattern
        -> TransitionT (RewriteRule Variable) m CommonStrategyPattern
    transitionRule' = OnePath.transitionRule

    strategy' :: Strategy (Prim (Pattern Variable) (RewriteRule Variable))
    strategy'
        | isRoot =
            onePathFirstStep targetPattern rewrites
        | otherwise =
            onePathFollowupStep
                targetPattern
                (RewriteRule . coerce <$> claims)
                rewrites

    rewrites :: [RewriteRule Variable]
    rewrites = coerce <$> axioms

    targetPattern :: Pattern Variable
    targetPattern =
        Pattern.fromTermLike
            . right
            . coerce
            $ target

    isRoot :: Bool
    isRoot = node == root
