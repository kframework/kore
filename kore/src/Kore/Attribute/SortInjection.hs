{-|
Module      : Kore.Attribute.SortInjection
Description : Sort injection symbol attribute
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com

-}
module Kore.Attribute.SortInjection
    ( SortInjection (..)
    , sortInjectionId, sortInjectionSymbol, sortInjectionAttribute
    ) where

import Prelude.Kore

import qualified Data.Monoid as Monoid
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

-- | @SortInjection@ represents the @sortInjection@ attribute for symbols.
newtype SortInjection = SortInjection { isSortInjection :: Bool }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)
    deriving (Semigroup, Monoid) via Monoid.Any

instance Default SortInjection where
    def = mempty

-- | Kore identifier representing the @sortInjection@ attribute symbol.
sortInjectionId :: Id
sortInjectionId = "sortInjection"

-- | Kore symbol representing the @sortInjection@ attribute.
sortInjectionSymbol :: SymbolOrAlias
sortInjectionSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = sortInjectionId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @sortInjection@ attribute.
sortInjectionAttribute :: AttributePattern
sortInjectionAttribute = attributePattern sortInjectionSymbol []

instance ParseAttributes SortInjection where
    parseAttribute =
        withApplication' $ \params args SortInjection { isSortInjection } -> do
            Parser.getZeroParams params
            Parser.getZeroArguments args
            when isSortInjection failDuplicate'
            return SortInjection { isSortInjection = True }
      where
        withApplication' = Parser.withApplication sortInjectionId
        failDuplicate' = Parser.failDuplicate sortInjectionId

instance From SortInjection Attributes where
    from SortInjection { isSortInjection } =
        Attributes [sortInjectionAttribute | isSortInjection]
