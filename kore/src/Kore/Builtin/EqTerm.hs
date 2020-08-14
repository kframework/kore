{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

 -}

module Kore.Builtin.EqTerm
    ( EqTerm (..)
    , matchEqTerm
    , unifyEqTerm
    ) where

import Prelude.Kore

import Control.Error
    ( MaybeT
    )
import qualified Control.Monad as Monad

import qualified Kore.Builtin.Bool as Bool
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.SideCondition as SideCondition
import Kore.Internal.TermLike as TermLike
import Kore.Step.Simplification.NotSimplifier
    ( NotSimplifier (..)
    )
import Kore.Step.Simplification.Simplify
    ( TermSimplifier
    )
import Kore.Unification.Unify as Unify

{- | An equality-like symbol applied to @term@-type arguments.
-}

data EqTerm term =
    EqTerm
        { symbol :: !Symbol
        , operand1, operand2 :: !term
        }
    deriving Show

{- | Match an equality-like symbol pattern.
-}
matchEqTerm
    :: (Symbol -> Bool)  -- ^ 'Symbol' selector
    -> TermLike variable
    -> Maybe (EqTerm (TermLike variable))
matchEqTerm selectSymbol (App_ symbol [operand1, operand2]) = do
    Monad.guard (selectSymbol symbol)
    return EqTerm { symbol, operand1, operand2 }
matchEqTerm _ _ = Nothing

{- | Unification for an equality-like symbol.

This function is suitable only for equality simplification.

 -}
unifyEqTerm
    :: forall variable unifier
    .  InternalVariable variable
    => MonadUnify unifier
    => TermSimplifier variable unifier
    -> NotSimplifier unifier
    -> EqTerm (TermLike variable)
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
unifyEqTerm unifyChildren (NotSimplifier notSimplifier) eqTerm termLike2
  | Just value2 <- Bool.matchBool termLike2
  = lift $ do
    solution <- unifyChildren operand1 operand2 & OrPattern.gather
    let solution' = fmap eraseTerm solution
    (if value2 then pure else notSimplifier SideCondition.top) solution'
        >>= Unify.scatter
  | otherwise = empty
  where
    EqTerm { operand1, operand2 } = eqTerm
    eraseTerm = Pattern.fromCondition_ . Pattern.withoutTerm
