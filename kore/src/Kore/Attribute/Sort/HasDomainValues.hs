{-|
Module      : Kore.Attribute.HasDomainValues
Description : Attribute saying whether a sort has domain values.
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
-}

module Kore.Attribute.Sort.HasDomainValues
    ( HasDomainValues (..)
    , hasDomainValuesId, hasDomainValuesSymbol, hasDomainValuesAttribute
    ) where

import Prelude.Kore

import qualified Data.Monoid as Monoid
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

-- | @HasDomainValues@ represents the @hasDomainValues@ attribute for symbols.
newtype HasDomainValues = HasDomainValues { getHasDomainValues :: Bool }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)
    deriving (Semigroup, Monoid) via Monoid.Any

instance Default HasDomainValues where
    def = mempty

-- | Kore identifier representing the @hasDomainValues@ attribute symbol.
hasDomainValuesId :: Id
hasDomainValuesId = "hasDomainValues"

-- | Kore symbol representing the @hasDomainValues@ attribute.
hasDomainValuesSymbol :: SymbolOrAlias
hasDomainValuesSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = hasDomainValuesId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @hasDomainValues@ attribute.
hasDomainValuesAttribute :: AttributePattern
hasDomainValuesAttribute = attributePattern hasDomainValuesSymbol []

instance ParseAttributes HasDomainValues where
    parseAttribute = parseBoolAttribute hasDomainValuesId

instance From HasDomainValues Attributes where
    from = toBoolAttributes hasDomainValuesAttribute
