{-|
Module      : Kore.Unification.Procedure
Description : Unification procedure.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Unification.Procedure
    ( unificationProcedure
    , unificationProcedureWorker
    ) where

import Prelude.Kore

import Kore.Internal.Condition
    ( Condition
    )
import qualified Kore.Internal.Pattern as Conditional
import Kore.Internal.SideCondition
    ( SideCondition
    )
import Kore.Internal.TermLike
import Kore.Log.InfoAttemptUnification
    ( infoAttemptUnification
    )
import Kore.Sort
    ( predicateSort
    )
import Kore.Step.Simplification.AndTerms
    ( termUnification
    )
import qualified Kore.Step.Simplification.Not as Not
import Kore.Step.Simplification.Simplify
    ( MonadSimplify
    , makeEvaluateTermCeil
    , simplifyCondition
    )
import qualified Kore.TopBottom as TopBottom
import Kore.Unification.UnificationProcedure
import Kore.Unification.UnifierT
    ( evalEnvUnifierT
    )
import Kore.Unification.Unify
    ( MonadUnify
    )
import qualified Kore.Unification.Unify as Monad.Unify
import Logic
    ( lowerLogicT
    )

-- |'unificationProcedure' attempts to simplify @t1 = t2@, assuming @t1@ and
-- @t2@ are terms (functional patterns) to a substitution.
-- If successful, it also produces a proof of how the substitution was obtained.
unificationProcedureWorker
    ::  ( InternalVariable variable
        , MonadUnify unifier
        )
    => SideCondition variable
    -> TermLike variable
    -> TermLike variable
    -> unifier (Condition variable)
unificationProcedureWorker sideCondition p1 p2
  | p1Sort /= p2Sort =
    Monad.Unify.explainAndReturnBottom "Cannot unify different sorts."  p1 p2
  | otherwise = infoAttemptUnification p1 p2 $ do
    pat <- termUnification Not.notSimplifier p1 p2
    TopBottom.guardAgainstBottom pat
    let (term, conditions) = Conditional.splitTerm pat
    orCeil <- makeEvaluateTermCeil sideCondition predicateSort term
    ceil' <- Monad.Unify.scatter orCeil
    lowerLogicT . simplifyCondition sideCondition
        $ Conditional.andCondition ceil' conditions
  where
    p1Sort = termLikeSort p1
    p2Sort = termLikeSort p2

unificationProcedure
    :: MonadSimplify simplifier
    => UnificationProcedure simplifier
unificationProcedure =
    UnificationProcedure $ \sideCondition term1 term2 ->
        unificationProcedureWorker sideCondition term1 term2
        & evalEnvUnifierT Not.notSimplifier
