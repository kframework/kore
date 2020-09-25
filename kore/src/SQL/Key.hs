{-|
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

Foreign keys for SQL tables.

-}

module SQL.Key
    ( Key(..)
    ) where

import Prelude.Kore

import Data.Int
    ( Int64
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Debug

{- | A foreign key into the table for type @a@.
 -}
newtype Key a = Key { getKey :: Int64 }
    deriving (Eq, Ord, Read, Show)
    deriving (Functor, Foldable)
    deriving (GHC.Generic)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)
