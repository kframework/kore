{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

 -}

module Kore.Attribute.Symbol.SymbolKywd
    ( SymbolKywd (..)
    , symbolKywdId, symbolKywdSymbol, symbolKywdAttribute
    ) where

import Prelude.Kore

import Data.Monoid
    ( Any (..)
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

-- | @SymbolKywd@ represents the @symbolKywd@ attribute for symbols.
newtype SymbolKywd = SymbolKywd { isSymbolKywd :: Bool }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)
    deriving (Semigroup, Monoid) via Any

instance Default SymbolKywd where
    def = mempty

-- | Kore identifier representing the @symbolKywd@ attribute symbol.
symbolKywdId :: Id
symbolKywdId = "symbol'Kywd'"

-- | Kore symbol representing the @symbolKywd@ attribute.
symbolKywdSymbol :: SymbolOrAlias
symbolKywdSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = symbolKywdId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @symbolKywd@ attribute.
symbolKywdAttribute :: AttributePattern
symbolKywdAttribute = attributePattern_ symbolKywdSymbol

instance ParseAttributes SymbolKywd where
    parseAttribute = parseBoolAttribute symbolKywdId

instance From SymbolKywd Attributes where
    from = toBoolAttributes symbolKywdAttribute
