{-|
Module      : Kore.Attribute.Overload
Description : Overloaded production attribute
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com

-}
module Kore.Attribute.Overload
    ( Overload (..)
    , overloadId, overloadSymbol, overloadAttribute
    ) where

import Prelude.Kore

import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

-- | @Overload@ represents the @overload@ attribute for symbols.
newtype Overload symbol =
    Overload
        { getOverload :: Maybe (symbol, symbol) }
    deriving (Eq, GHC.Generic, Ord, Show, Functor)

instance SOP.Generic (Overload symbol)

instance SOP.HasDatatypeInfo (Overload symbol)

instance Debug symbol => Debug (Overload symbol)

instance (Debug symbol, Diff symbol) => Diff (Overload symbol)

instance Semigroup (Overload symbol) where
    (<>) a@(Overload (Just _)) _ = a
    (<>) _                     b = b

instance Monoid (Overload symbol) where
    mempty = Overload { getOverload = Nothing }

instance Default (Overload symbol) where
    def = mempty

instance NFData symbol => NFData (Overload symbol)

-- | Kore identifier representing the @overload@ attribute symbol.
overloadId :: Id
overloadId = "overload"

-- | Kore symbol representing the @overload@ attribute.
overloadSymbol :: SymbolOrAlias
overloadSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = overloadId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @overload@ attribute.
overloadAttribute
    :: SymbolOrAlias
    -> SymbolOrAlias
    -> AttributePattern
overloadAttribute symbol1 symbol2 =
    attributePattern overloadSymbol
        [ attributePattern_ symbol1
        , attributePattern_ symbol2
        ]

instance ParseAttributes (Overload SymbolOrAlias) where
    parseAttribute = withApplication' parseApplication
      where
        parseApplication params args Overload { getOverload }
          | Just _ <- getOverload = failDuplicate'
          | otherwise = do
            Parser.getZeroParams params
            (arg1, arg2) <- Parser.getTwoArguments args
            symbol1 <- Parser.getSymbolOrAlias arg1
            symbol2 <- Parser.getSymbolOrAlias arg2
            return Overload { getOverload = Just (symbol1, symbol2) }
        withApplication' = Parser.withApplication overloadId
        failDuplicate' = Parser.failDuplicate overloadId

instance From symbol SymbolOrAlias => From (Overload symbol) Attributes where
    from =
        maybe def toAttribute . getOverload
      where
        toAttribute (symbol1, symbol2) =
            from @AttributePattern
            $ overloadAttribute (from symbol1) (from symbol2)
