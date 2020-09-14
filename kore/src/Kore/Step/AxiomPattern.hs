{-|
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

-}

module Kore.Step.AxiomPattern
    ( AxiomPattern (..)
    ) where

import Prelude.Kore

import Kore.Internal.TermLike
    ( InternalVariable
    , TermLike
    , VariableName
    )
import qualified Kore.Internal.TermLike as TermLike
import Kore.Step.RulePattern
    ( RewriteRule
    , rewriteRuleToTerm
    )
import Kore.Unparser
    ( Unparse (..)
    )

-- | A wrapper over 'TermLike variable'. It represents a rewrite axiom
-- or claim as a Matching Logic pattern.
newtype AxiomPattern variable =
    AxiomPattern { getAxiomPattern :: TermLike variable }
    deriving (Show, Eq)

instance Unparse (AxiomPattern VariableName) where
    unparse = unparse . getAxiomPattern
    unparse2 = unparse2 . getAxiomPattern

instance InternalVariable variable =>
    From (RewriteRule variable) (AxiomPattern variable)
  where
    from = AxiomPattern . rewriteRuleToTerm
