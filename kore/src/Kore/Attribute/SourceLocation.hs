{-|
Module      : Kore.Attribute.SourceLocation
Description : Source and location attribute
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com

-}
{-# LANGUAGE Strict #-}

module Kore.Attribute.SourceLocation
    ( SourceLocation (..)
    , Source (..)
    , Location (..)
    ) where

import Prelude.Kore

import Control.Monad
    ( (>=>)
    )
import Data.Default
import Data.Generics.Product
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Location
    ( LineColumn (..)
    , Location (..)
    )
import Kore.Attribute.Parser
    ( Attributes
    , ParseAttributes (..)
    )
import Kore.Attribute.Source
    ( Source (..)
    )
import Kore.Debug
import Kore.Syntax
    ( FileLocation (..)
    )
import Pretty
    ( Pretty
    )
import qualified Pretty

data SourceLocation =
    SourceLocation
    { location :: !Location
    , source   :: !Source
    }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance Default SourceLocation where
    def = SourceLocation def def

instance ParseAttributes SourceLocation where
    parseAttribute attr =
        typed @Location (parseAttribute attr)
        >=> typed @Source (parseAttribute attr)

instance From SourceLocation Attributes where
    -- TODO (thomas.tuegel): Implement
    from _ = def

instance From FileLocation SourceLocation where
    from FileLocation { fileName, line, column } =
        SourceLocation
            { location = Location
                { start = Just LineColumn { line, column }
                , end = Nothing
                }
            , source = Source (Just fileName)
            }

instance Pretty SourceLocation where
    pretty SourceLocation
        { location = Location { start , end }
        , source = (Source (Just file))
        }
      = Pretty.pretty file <> loc

      where
        loc :: Pretty.Doc ann
        loc =
            case start of
                Just lc -> ":" <> prettyLC lc <> maybeLC end
                Nothing -> Pretty.emptyDoc

        prettyLC :: LineColumn -> Pretty.Doc ann
        prettyLC LineColumn { line, column } =
            Pretty.hcat
                [ Pretty.pretty line
                , ":"
                , Pretty.pretty column
                ]

        maybeLC :: Maybe LineColumn -> Pretty.Doc ann
        maybeLC Nothing = Pretty.emptyDoc
        maybeLC (Just elc) = "-" <> prettyLC elc
    pretty _ = ""
