{-|
Module      : Data.Kore.ASTVerifier.AttributesVerifier
Description : Tools for verifying the wellformedness of Kore 'Attributes'.
Copyright   : (c) Runtime Verification, 2018
License     : UIUC/NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : POSIX
-}
module Data.Kore.ASTVerifier.AttributesVerifier (verifyAttributes,
                                                 AttributesVerification (..))
  where

import           Data.Kore.AST.Kore
import           Data.Kore.ASTVerifier.Error
import           Data.Kore.ASTVerifier.PatternVerifier
import           Data.Kore.Error
import           Data.Kore.IndexedModule.IndexedModule
import qualified Data.Set                              as Set

data AttributesVerification = VerifyAttributes | DoNotVerifyAttributes

{-|'verifyAttributes' verifies the weldefinedness of the given attributes.
-}
verifyAttributes
    :: Attributes
    -> IndexedModule
    -- ^ Module with the declarations visible in these atributes.
    -> Set.Set UnifiedSortVariable
    -- ^ Sort variables visible in these atributes.
    -> AttributesVerification
    -> Either (Error VerifyError) VerifySuccess
verifyAttributes
    (Attributes patterns) indexedModule sortVariables VerifyAttributes
  = do
    withContext
        "attributes"
        (mapM_
            (\p -> verifyPattern p Nothing indexedModule sortVariables)
            patterns
        )
    verifySuccess
verifyAttributes _ _ _ DoNotVerifyAttributes =
    verifySuccess
