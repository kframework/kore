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

import qualified Control.Monad as Monad

import Kore.Attribute.Parser as Parser

{- | @Idem@ represents the @idem@ attribute for axioms.
 -}
newtype Idem = Idem { isIdem :: Bool }
    deriving (Eq, Ord, Show, Generic)

instance NFData Idem

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
    parseAttribute =
        withApplication' $ \params args Idem { isIdem } -> do
            Parser.getZeroParams params
            Parser.getZeroArguments args
            Monad.when isIdem failDuplicate'
            return Idem { isIdem = True }
      where
        withApplication' = Parser.withApplication idemId
        failDuplicate' = Parser.failDuplicate idemId

    toAttributes Idem { isIdem } = Attributes [idemAttribute | isIdem]
