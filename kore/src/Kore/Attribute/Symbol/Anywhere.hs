{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

 -}

module Kore.Attribute.Symbol.Anywhere
    ( Anywhere (..)
    , anywhereId, anywhereSymbol, anywhereAttribute
    ) where

import Prelude.Kore

import qualified Data.Monoid as Monoid
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

-- | @Anywhere@ represents the @anywhere@ attribute for symbols.
newtype Anywhere = Anywhere { isAnywhere :: Bool }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)
    deriving (Semigroup, Monoid) via Monoid.Any

instance Default Anywhere where
    def = mempty

-- | Kore identifier representing the @anywhere@ attribute symbol.
anywhereId :: Id
anywhereId = "anywhere"

-- | Kore symbol representing the @anywhere@ attribute.
anywhereSymbol :: SymbolOrAlias
anywhereSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = anywhereId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @anywhere@ attribute.
anywhereAttribute :: AttributePattern
anywhereAttribute = attributePattern_ anywhereSymbol

instance ParseAttributes Anywhere where
    parseAttribute = parseBoolAttribute anywhereId

instance From Anywhere Attributes where
    from = toBoolAttributes anywhereAttribute
