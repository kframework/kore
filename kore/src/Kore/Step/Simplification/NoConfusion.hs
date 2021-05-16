{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}
module Kore.Step.Simplification.NoConfusion (
    equalInjectiveHeadsAndEquals,
    constructorAndEqualsAssumesDifferentHeads,
    matchEqualInjectiveHeadsAndEquals,
    matchConstructorAndEqualsAssumesDifferentHeads,
) where

import qualified Control.Monad as Monad
import Kore.Internal.Pattern (
    Pattern,
 )
import qualified Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.Symbol as Symbol
import Kore.Internal.TermLike
import Kore.Rewriting.RewritingVariable (
    RewritingVariableName,
 )
import Kore.Step.Simplification.Simplify as Simplifier
import Kore.Unification.Unify as Unify
import Prelude.Kore hiding (
    concat,
 )

data UnifyEqualInjectiveHeadsAndEquals = UnifyEqualInjectiveHeadsAndEquals
    { firstHead :: Symbol
    , firstChildren :: [TermLike RewritingVariableName]
    , secondChildren :: [TermLike RewritingVariableName]
    }

matchEqualInjectiveHeadsAndEquals ::
    TermLike RewritingVariableName ->
    TermLike RewritingVariableName ->
    Maybe UnifyEqualInjectiveHeadsAndEquals
matchEqualInjectiveHeadsAndEquals first second
    | App_ firstHead firstChildren <- first
      , App_ secondHead secondChildren <- second
      , Symbol.isInjective firstHead
      , Symbol.isInjective secondHead
      , firstHead == secondHead --is one of the above redundant in light of this?
        =
        Just
            UnifyEqualInjectiveHeadsAndEquals
                { firstHead
                , firstChildren
                , secondChildren
                }
    | otherwise = Nothing
{-# INLINE matchEqualInjectiveHeadsAndEquals #-}

{- | Unify two application patterns with equal, injective heads.

This includes constructors and sort injections.

See also: 'Attribute.isInjective', 'Attribute.isSortInjection',
'Attribute.isConstructor'
-}
equalInjectiveHeadsAndEquals ::
    MonadUnify unifier =>
    HasCallStack =>
    -- | Used to simplify subterm "and".
    TermSimplifier RewritingVariableName unifier ->
    UnifyEqualInjectiveHeadsAndEquals ->
    unifier (Pattern RewritingVariableName)
equalInjectiveHeadsAndEquals
    termMerger
    unifyData =
        do
            children <- Monad.zipWithM termMerger firstChildren secondChildren
            let merged = foldMap Pattern.withoutTerm children
                -- TODO (thomas.tuegel): This is tricky!
                -- Unifying the symbol's children may have produced new patterns
                -- which allow evaluating the symbol. It is possible this pattern
                -- is not actually fully simplified!
                term =
                    (markSimplified . mkApplySymbol firstHead)
                        (Pattern.term <$> children)
            return (Pattern.withCondition term merged)
      where
        UnifyEqualInjectiveHeadsAndEquals
            { firstHead
            , firstChildren
            , secondChildren
            } = unifyData

-- data ConstructorAndEqualsAssumesDifferentHeads = ConstructorAndEqualsAssumesDifferentHeads
--     { firstHead, secondHead :: Symbol
--     }

matchConstructorAndEqualsAssumesDifferentHeads ::
    (Symbol -> Bool) ->
    TermLike RewritingVariableName ->
    TermLike RewritingVariableName ->
    Maybe ()
matchConstructorAndEqualsAssumesDifferentHeads
    isOverloaded
    first
    second
        | App_ firstHead _ <- first
          , App_ secondHead _ <- second
          , firstHead /= secondHead
          , Symbol.isConstructor firstHead || isOverloaded firstHead
          , Symbol.isConstructor secondHead || isOverloaded secondHead =
            Just ()
        | otherwise = empty
{-# INLINE matchConstructorAndEqualsAssumesDifferentHeads #-}

{- | Unify two constructor application patterns.

Assumes that the two patterns were already tested for equality and were found
to be different; therefore their conjunction is @\\bottom@.
-}
constructorAndEqualsAssumesDifferentHeads ::
    MonadUnify unifier =>
    TermLike RewritingVariableName ->
    TermLike RewritingVariableName ->
    unifier a
constructorAndEqualsAssumesDifferentHeads
    first
    second =
        do
            explainBottom
                "Cannot unify different constructors or incompatible \
                \sort injections."
                first
                second
            empty
