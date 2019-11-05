{-|
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
-}
module Kore.Step.Simplification.InternalBytes
    ( simplify
    ) where

import Kore.Internal.InternalBytes
import Kore.Internal.OrPattern
    ( OrPattern
    )
import Kore.Internal.TermLike
import Kore.Step.Simplification.Simplify
    ( SimplifierVariable
    )

simplify :: SimplifierVariable variable => InternalBytes -> OrPattern variable
simplify = pure . pure . mkInternalBytes'
