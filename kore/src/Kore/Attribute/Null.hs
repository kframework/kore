{-|
Module      : Kore.Attribute.Null
Description : Null attribute parser
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com

The 'Null' attribute is used when we need a type to satisfy the attribute
parser, but we do not actually care to parse any attributes. This parser simply
ignores all attributes.

This module is intended to be imported qualified:
@
import qualified Kore.Attribute.Null as Attribute
@

-}
module Kore.Attribute.Null
    ( Null (..)
    ) where

import Data.Default

import Kore.Attribute.Parser

data Null = Null
    deriving (Eq, Ord, Show)

instance Default Null where
    def = Null

instance ParseAttributes Null where
    parseAttribute _ Null = return Null
