{-|
Module      : Kore.Step.RecursiveAttributes
Description : Tools for using pattern attributes in step execution
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : phillip.harris@runtimeverification.com
Stability   : experimental
Portability : portable
-}

module Kore.Step.RecursiveAttributes
    ( isFunctionalPattern
    , isFunctionPattern
    , isTotalPattern
    ) where


import           Kore.ASTUtils.SmartPatterns
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools )
import qualified Kore.IndexedModule.MetadataTools as MetadataTools
                 ( MetadataTools (..) )
import           Kore.Step.Pattern
import           Kore.Step.StepperAttributes

recursivelyCheckHeadProperty
    ::  forall level variable .
        (StepperAttributes -> Bool)
    -> MetadataTools level StepperAttributes
    -> StepPattern level variable
    -> Bool
recursivelyCheckHeadProperty prop tools = go
  where
    go (App_ patHead patChildren) = prop atts && all go patChildren
        where atts = MetadataTools.symAttributes tools patHead
    go (DV_ _ pat) = all go pat
    go (Var_ _)           = True
    go (StringLiteral_ _) = True
    go (CharLiteral_ _)   = True
    go _ = False

isFunctionalPattern, isFunctionPattern, isTotalPattern
    ::  forall level variable.
        MetadataTools level StepperAttributes
    -> StepPattern level variable
    -> Bool
--TODO(traiansf): we assume below that the pattern does not contain
--sort injection symbols where the parameter sorts are not in subsort relation.
isFunctionalPattern = recursivelyCheckHeadProperty isFunctional
isFunctionPattern = recursivelyCheckHeadProperty isFunction
isTotalPattern = recursivelyCheckHeadProperty isTotal
