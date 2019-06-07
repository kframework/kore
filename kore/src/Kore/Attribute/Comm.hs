{-|
Module      : Kore.Attribute.Comm
Description : Commutativity axiom attribute
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com

-}
module Kore.Attribute.Comm
    ( Comm (..)
    , commId, commSymbol, commAttribute
    ) where

import           Control.DeepSeq
                 ( NFData )
import qualified Control.Monad as Monad
import           Data.Default
import           GHC.Generics
                 ( Generic )

import Kore.Attribute.Parser as Parser

{- | @Comm@ represents the @comm@ attribute for axioms.
 -}
newtype Comm = Comm { isComm :: Bool }
    deriving (Eq, Ord, Show, Generic)

instance NFData Comm

instance Default Comm where
    def = Comm False

-- | Kore identifier representing the @comm@ attribute symbol.
commId :: Id
commId = "comm"

-- | Kore symbol representing the @comm@ attribute.
commSymbol :: SymbolOrAlias
commSymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = commId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing the @comm@ attribute.
commAttribute :: AttributePattern
commAttribute = attributePattern_ commSymbol

instance ParseAttributes Comm where
    parseAttribute =
        withApplication' $ \params args Comm { isComm } -> do
            Parser.getZeroParams params
            Parser.getZeroArguments args
            Monad.when isComm failDuplicate'
            return Comm { isComm = True }
      where
        withApplication' = Parser.withApplication commId
        failDuplicate' = Parser.failDuplicate commId

    toAttributes Comm { isComm } =
        Attributes $ if isComm then [commAttribute] else []
