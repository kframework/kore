{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}
module Kore.Syntax.Module
    ( ModuleName (..)
    , getModuleNameForError
    , Module (..)
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import           Data.Hashable
                 ( Hashable (..) )
import           Data.Maybe
                 ( catMaybes )
import           Data.String
                 ( IsString )
import           Data.Text
                 ( Text )
import qualified Data.Text as Text
import qualified Data.Text.Prettyprint.Doc as Pretty
import           GHC.Generics
                 ( Generic )

import Kore.Attribute.Attributes
import Kore.Unparser

{- | 'ModuleName' corresponds to the @module-name@ syntactic category
from the Semantics of K, Section 9.1.6 (Declaration and Definitions).
-}
newtype ModuleName = ModuleName { getModuleName :: Text }
    deriving (Eq, Generic, IsString, Ord, Show)

instance Hashable ModuleName

instance NFData ModuleName

instance Unparse ModuleName where
    unparse = Pretty.pretty . getModuleName
    unparse2 = Pretty.pretty . getModuleName


getModuleNameForError :: ModuleName -> String
getModuleNameForError = Text.unpack . getModuleName

{-|A 'Module' consists of a 'ModuleName' a list of 'Sentence's and some
'Attributes'.

They correspond to the second, third and forth non-terminals of the @definition@
syntactic category from the Semantics of K, Section 9.1.6
(Declaration and Definitions).
-}
data Module (sentence :: *) =
    Module
        { moduleName       :: !ModuleName
        , moduleSentences  :: ![sentence]
        , moduleAttributes :: !Attributes
        }
    deriving (Eq, Functor, Foldable, Generic, Show, Traversable)

instance Hashable sentence => Hashable (Module sentence)

instance NFData sentence => NFData (Module sentence)

instance Unparse sentence => Unparse (Module sentence) where
    unparse
        Module { moduleName, moduleSentences, moduleAttributes }
      =
        (Pretty.vsep . catMaybes)
            [ Just ("module" Pretty.<+> unparse moduleName)
            , case moduleSentences of
                [] -> Nothing
                _ ->
                    (Just . Pretty.indent 4 . Pretty.vsep)
                        (unparse <$> moduleSentences)
            , Just "endmodule"
            , Just (unparse moduleAttributes)
            ]

    unparse2
        Module { moduleName, moduleSentences, moduleAttributes }
      =
        (Pretty.vsep . catMaybes)
            [ Just ("module" Pretty.<+> unparse2 moduleName)
            , case moduleSentences of
                [] -> Nothing
                _ ->
                    (Just . Pretty.indent 4 . Pretty.vsep)
                        (unparse2 <$> moduleSentences)
            , Just "endmodule"
            , Just (unparse2 moduleAttributes)
            ]
