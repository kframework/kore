{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

 -}
module Kore.Unification.UnifierT
    ( UnifierT (..)
    , lowerExceptT
    , runUnifierT
    , maybeUnifierT
    , substitutionSimplifier
    -- * Re-exports
    , module Kore.Unification.Unify
    ) where

import Prelude.Kore

import Control.Error
import Control.Monad
    ( MonadPlus
    )
import qualified Control.Monad.Except as Error
import qualified Control.Monad.Morph as Morph
import Control.Monad.Trans.Class
    ( MonadTrans (..)
    )

import Branch
    ( BranchT
    )
import qualified Branch as BranchT
import Kore.Profiler.Data
    ( MonadProfiler
    )
import qualified Kore.Step.Simplification.Condition as ConditionSimplifier
import Kore.Step.Simplification.Simplify
    ( ConditionSimplifier (..)
    , InternalVariable
    , MonadSimplify (..)
    )
import Kore.Unification.Error
import Kore.Unification.SubstitutionSimplifier
    ( substitutionSimplifier
    )
import Kore.Unification.Unify
import Log
    ( MonadLog (..)
    )
import SMT
    ( MonadSMT (..)
    )

newtype UnifierT (m :: * -> *) a =
    UnifierT { getUnifierT :: BranchT (ExceptT UnificationError m) a }
    deriving (Functor, Applicative, Monad, Alternative, MonadPlus)

instance MonadTrans UnifierT where
    lift = UnifierT . lift . lift
    {-# INLINE lift #-}

deriving instance MonadLog m => MonadLog (UnifierT m)

deriving instance MonadSMT m => MonadSMT (UnifierT m)

deriving instance MonadProfiler m => MonadProfiler (UnifierT m)

instance MonadSimplify m => MonadSimplify (UnifierT m) where
    localSimplifierTermLike locally =
        \(UnifierT branchT) ->
            UnifierT
                (BranchT.mapBranchT
                    (Morph.hoist (localSimplifierTermLike locally))
                    branchT
                )
    {-# INLINE localSimplifierTermLike #-}

    localSimplifierAxioms locally =
        \(UnifierT branchT) ->
            UnifierT
                (BranchT.mapBranchT
                    (Morph.hoist (localSimplifierAxioms locally))
                    branchT
                )
    {-# INLINE localSimplifierAxioms #-}

    simplifyCondition sideCondition condition =
        simplifyCondition' sideCondition condition
      where
        ConditionSimplifier simplifyCondition' =
            ConditionSimplifier.create substitutionSimplifier
    {-# INLINE simplifyCondition #-}

instance MonadSimplify m => MonadUnify (UnifierT m) where
    throwUnificationError = UnifierT . lift . Error.throwError
    {-# INLINE throwUnificationError #-}

    gather = UnifierT . lift . BranchT.gather . getUnifierT
    {-# INLINE gather #-}

    scatter = UnifierT . BranchT.scatter
    {-# INLINE scatter #-}

-- | Lower an 'ExceptT UnificationError' into a 'MonadUnify'.
lowerExceptT
    :: MonadUnify unifier
    => ExceptT UnificationError unifier a
    -> unifier a
lowerExceptT e = runExceptT e >>= either throwUnificationError pure

runUnifierT
    :: MonadSimplify m
    => UnifierT m a
    -> m (Either UnificationError [a])
runUnifierT = runExceptT . BranchT.gather . getUnifierT

{- | Run a 'Unifier', returning 'Nothing' upon error.
 -}
maybeUnifierT :: MonadSimplify m => UnifierT m a -> MaybeT m [a]
maybeUnifierT = hushT . BranchT.gather . getUnifierT
