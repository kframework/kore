{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

-}

module Kore.Log.InfoExecDepth
    ( InfoExecDepth (..)
    , ExecDepth (..)
    , infoExecDepth
    ) where

import Prelude.Kore

import qualified Data.Semigroup as Semigroup
import Numeric.Natural
    ( Natural
    )

import Log
import Pretty
    ( Pretty
    )
import qualified Pretty

newtype ExecDepth = ExecDepth { getExecDepth :: Natural }
    deriving (Eq, Ord, Show)
    deriving (Enum)
    deriving (Semigroup) via (Semigroup.Max Natural)

instance Pretty ExecDepth where
    pretty execDepth =
        Pretty.hsep ["exec depth:", Pretty.pretty (getExecDepth execDepth)]

data InfoExecDepth = InfoExecDepth ExecDepth
    deriving (Show)

instance Pretty InfoExecDepth where
    pretty (InfoExecDepth execDepth) =
        Pretty.hsep ["execution complete:", Pretty.pretty execDepth]

instance Entry InfoExecDepth where
    entrySeverity _ = Info
    helpDoc _ = "log depth of execution graph"

infoExecDepth :: MonadLog log => ExecDepth -> log ()
infoExecDepth = logEntry . InfoExecDepth
