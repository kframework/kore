{-|
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

-}

module Kore.Reachability.AllPathClaim
    ( AllPathClaim (..)
    , allPathRuleToTerm
    , Rule (..)
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import Control.Monad
    ( foldM
    )
import Data.Generics.Wrapped
    ( _Unwrapped
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import qualified Kore.Attribute.Axiom as Attribute
import Kore.Debug
import Kore.Internal.Alias
    ( Alias (aliasConstructor)
    )
import qualified Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.TermLike
    ( Id (getId)
    , TermLike
    , VariableName
    , weakAlwaysFinally
    )
import qualified Kore.Internal.TermLike as TermLike
import Kore.Reachability.Claim
import Kore.Reachability.ClaimState
    ( ClaimState (..)
    , retractRewritable
    )
import Kore.Rewriting.RewritingVariable
    ( RewritingVariableName
    , mkRuleVariable
    )
import Kore.Rewriting.UnifyingRule
    ( UnifyingRule (..)
    )
import Kore.Step.AxiomPattern
import Kore.Step.ClaimPattern as ClaimPattern
import Kore.Step.Simplification.Simplify
    ( MonadSimplify
    )
import Kore.Step.Transition
    ( TransitionT
    )
import qualified Kore.Syntax.Sentence as Syntax
import Kore.TopBottom
    ( TopBottom (..)
    )
import Kore.Unparser
    ( Unparse (..)
    )

-- | All-Path-Claim claim pattern.
newtype AllPathClaim =
    AllPathClaim { getAllPathClaim :: ClaimPattern }
    deriving (Eq, GHC.Generic, Ord, Show)

instance NFData AllPathClaim

instance SOP.Generic AllPathClaim

instance SOP.HasDatatypeInfo AllPathClaim

instance Debug AllPathClaim

instance Diff AllPathClaim

instance Unparse AllPathClaim where
    unparse claimPattern' =
        unparse $ allPathRuleToTerm claimPattern'
    unparse2 claimPattern' =
        unparse2 $ allPathRuleToTerm claimPattern'

instance TopBottom AllPathClaim where
    isTop _ = False
    isBottom _ = False

instance From AllPathClaim Attribute.SourceLocation where
    from = Attribute.sourceLocation . attributes . getAllPathClaim

instance From AllPathClaim Attribute.Label where
    from = Attribute.label . attributes . getAllPathClaim

instance From AllPathClaim Attribute.RuleIndex where
    from = Attribute.identifier . attributes . getAllPathClaim

instance From AllPathClaim Attribute.Trusted where
    from = Attribute.trusted . attributes . getAllPathClaim

-- | Converts an 'AllPathClaim' into its term representation.
-- This is intended to be used only in unparsing situations,
-- as some of the variable information related to the
-- rewriting algorithm is lost.
allPathRuleToTerm :: AllPathClaim -> TermLike VariableName
allPathRuleToTerm (AllPathClaim claimPattern') =
    claimPatternToTerm TermLike.WAF claimPattern'

instance UnifyingRule AllPathClaim where
    type UnifyingRuleVariable AllPathClaim = RewritingVariableName

    matchingPattern (AllPathClaim claim) = matchingPattern claim

    precondition (AllPathClaim claim) = precondition claim

    refreshRule stale (AllPathClaim claim) =
        AllPathClaim <$> refreshRule stale claim

instance From AllPathClaim (AxiomPattern VariableName) where
    from = AxiomPattern . allPathRuleToTerm

instance From AllPathClaim (AxiomPattern RewritingVariableName) where
    from =
        AxiomPattern
        . TermLike.mapVariables (pure mkRuleVariable)
        . allPathRuleToTerm

instance Claim AllPathClaim where

    newtype Rule AllPathClaim =
        AllPathRewriteRule
        { unRuleAllPath :: RewriteRule RewritingVariableName }
        deriving (GHC.Generic, Show, Unparse)

    simplify = simplify' _Unwrapped
    checkImplication = checkImplication' _Unwrapped
    applyClaims claims = deriveSeqClaim _Unwrapped AllPathClaim claims

    applyAxioms axiomss = \claim ->
        foldM applyAxioms1 (Remaining claim) axiomss
      where
        applyAxioms1 claimState axioms
          | Just claim <- retractRewritable claimState =
            deriveParAxiomAllPath axioms claim
            >>= simplifyRemainder
          | otherwise =
            pure claimState

        simplifyRemainder claimState =
            case claimState of
                Remaining claim -> Remaining <$> simplify claim
                _ -> return claimState

instance SOP.Generic (Rule AllPathClaim)

instance SOP.HasDatatypeInfo (Rule AllPathClaim)

instance Debug (Rule AllPathClaim)

instance Diff (Rule AllPathClaim)

instance From (Rule AllPathClaim) Attribute.PriorityAttributes where
    from = from @(RewriteRule _) . unRuleAllPath

instance ClaimExtractor AllPathClaim where
    extractClaim (attributes, sentence) =
        case termLike of
            TermLike.Implies_ _
                (TermLike.And_ _ requires lhs)
                (TermLike.ApplyAlias_ alias [rhs])
              | aliasId == weakAlwaysFinally -> do
                let rhs' = TermLike.mapVariables (pure mkRuleVariable) rhs
                    attributes' =
                        Attribute.mapAxiomVariables
                            (pure mkRuleVariable)
                            attributes
                    (right', existentials') =
                        ClaimPattern.termToExistentials rhs'
                pure $ AllPathClaim $ ClaimPattern.refreshExistentials
                    ClaimPattern
                    { ClaimPattern.left =
                        Pattern.fromTermAndPredicate
                            lhs
                            (Predicate.wrapPredicate requires)
                        & Pattern.mapVariables (pure mkRuleVariable)
                    , ClaimPattern.right = parseRightHandSide right'
                    , ClaimPattern.existentials = existentials'
                    , ClaimPattern.attributes = attributes'
                    }
              where
                aliasId = (getId . aliasConstructor) alias
            _ -> Nothing
      where
        termLike =
            (Syntax.sentenceAxiomPattern . Syntax.getSentenceClaim) sentence

deriveParAxiomAllPath
    ::  MonadSimplify simplifier
    =>  [Rule AllPathClaim]
    ->  AllPathClaim
    ->  TransitionT (AppliedRule AllPathClaim) simplifier
            (ClaimState AllPathClaim)
deriveParAxiomAllPath rules =
    derivePar' _Unwrapped AllPathRewriteRule rewrites
  where
    rewrites = unRuleAllPath <$> rules
