{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}
module Kore.Step.Simplification.Pattern
    ( simplifyTopConfiguration
    , simplify
    ) where

import Prelude.Kore


import qualified Kore.Internal.Conditional as Conditional
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Conditional (..)
    , Pattern
    )
import Kore.Internal.SideCondition
    ( SideCondition
    )
import qualified Kore.Internal.SideCondition as SideCondition
    ( andCondition
    , topTODO
    )
import Kore.Internal.Substitution
    ( toMap
    )
import Kore.Internal.TermLike
    ( pattern Exists_
    )
import Kore.Step.Simplification.Simplify
    ( InternalVariable
    , MonadSimplify
    , simplifyCondition
    , simplifyConditionalTerm
    )
import Kore.Substitute
    ( substitute
    )

{-| Simplifies the pattern without a side-condition (i.e. it's top)
and removes the exists quantifiers at the top.
-}
simplifyTopConfiguration
    :: forall variable simplifier
    .  InternalVariable variable
    => MonadSimplify simplifier
    => Pattern variable
    -> simplifier (OrPattern variable)
simplifyTopConfiguration patt = do
    simplified <- simplify SideCondition.topTODO patt
    return (OrPattern.map removeTopExists simplified)
  where
    removeTopExists :: Pattern variable -> Pattern variable
    removeTopExists p@Conditional{ term = Exists_ _ _ quantified } =
        removeTopExists p {term = quantified}
    removeTopExists p = p

{-| Simplifies an 'Pattern', returning an 'OrPattern'.
-}
simplify
    :: InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> Pattern variable
    -> simplifier (OrPattern variable)
simplify sideCondition pattern' =
    OrPattern.observeAllT $ do
        withSimplifiedCondition <- simplifyCondition sideCondition pattern'
        let (term, simplifiedCondition) =
                Conditional.splitTerm withSimplifiedCondition
            term' = substitute (toMap $ substitution simplifiedCondition) term
            termSideCondition =
                sideCondition `SideCondition.andCondition` simplifiedCondition
        simplifiedTerm <- simplifyConditionalTerm termSideCondition term'
        let simplifiedPattern =
                Conditional.andCondition simplifiedTerm simplifiedCondition
        simplifyCondition sideCondition simplifiedPattern
