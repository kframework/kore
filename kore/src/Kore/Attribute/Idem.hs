{-|
Module      : Kore.Attribute.Idem
Description : Idempotency axiom attribute
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com

-}
module Kore.Attribute.Idem
    ( Idem (..)
    , idemId, idemSymbol, idemAttribute
    ) where

import Prelude.Kore

import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

{- | @Idem@ represents the @idem@ attribute for axioms.
 -}
newtype Idem = Idem { isIdem :: Bool }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Default Idem where
    def = Idem False

-- | Kore identifier representing the @idem@ attribute symbol.
idemId :: Id
idemId = "idem"

-- | Kore symbol representing the @idem@ attribute.
idemSymbol :: SymbolOrAlias
idemSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = idemId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @idem@ attribute.
idemAttribute :: AttributePattern
idemAttribute = attributePattern_ idemSymbol

instance ParseAttributes Idem where
    parseAttribute = parseBoolAttribute idemId

instance From Idem Attributes where
    from = toBoolAttributes idemAttribute
