{-|
Module      : Data.Kore.ASTVerifier.DefinitionVerifier
Description : Tools for verifying the wellformedness of a Kore 'Definiton'.
Copyright   : (c) Runtime Verification, 2018
License     : UIUC/NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : POSIX
-}
module Data.Kore.ASTVerifier.DefinitionVerifier
    ( defaultAttributesVerification
    , verifyDefinition
    , verifyAndIndexDefinition
    , verifyKoreDefinition
    , AttributesVerification (..)
    ) where

import           Control.Monad                            (foldM, foldM_)
import           Data.Kore.AST.Common
import           Data.Kore.AST.Kore
import           Data.Kore.ASTVerifier.AttributesVerifier
import           Data.Kore.ASTVerifier.Error
import           Data.Kore.ASTVerifier.ModuleVerifier
import           Data.Kore.Error
import           Data.Kore.Implicit.Attributes
import           Data.Kore.Implicit.Definitions           (uncheckedAttributesDefinition,
                                                           uncheckedKoreModules)
import           Data.Kore.IndexedModule.IndexedModule
import           Data.Kore.MetaML.MetaToKore

import qualified Data.Map                                 as Map
import qualified Data.Set                                 as Set

{-|'verifyDefinition' verifies the welformedness of a Kore 'Definition'.

It does not fully verify the validity of object-meta combinations of patterns,
e.g.:

@
  axiom{S1,S2,R}
    \equals{Ctxt{S1,S2},R}(
      gamma{S1,S2}(
        #variableToPattern{}(#X:#Variable{}),
        #P:#Pattern{}),
      \exists{Ctxt{S1,S2}}(
        #X:#Variable{},
        gamma0{S1,S2}(
          #variableToPattern{}(#X:#Variable{}),
          #P:#Pattern{}))) []
@

-}
verifyDefinition
    :: AttributesVerification
    -> KoreDefinition
    -> Either (Error VerifyError) VerifySuccess
verifyDefinition attributesVerification definition = do
    verifyAndIndexDefinition attributesVerification definition
    verifySuccess

{-|'verifyAndIndexDefinition' verifies a definition and returns an indexed
collection of the definition's modules.
-}
verifyAndIndexDefinition
    :: AttributesVerification
    -> KoreDefinition
    -> Either (Error VerifyError) (Map.Map ModuleName KoreIndexedModule)
verifyAndIndexDefinition attributesVerification definition = do
    (implicitIndexedModules, implicitIndexedModule, defaultNames) <-
        indexImplicitModules

    foldM_ verifyUniqueNames defaultNames (definitionModules definition)

    implicitIndexedModules <-
        indexModuleIfNeeded
            moduleWithMetaSorts
            nameToModule
            (Map.singleton defaultModuleName defaultModuleWithMetaSorts)
            implicitModule
    let
        implicitIndexedModule =
            case
                Map.lookup (moduleName implicitModule) implicitIndexedModules
            of
                Just m -> m
    indexedModules <-
        foldM
            (indexModuleIfNeeded
                implicitIndexedModule
                nameToModule
            )
            implicitIndexedModules
            (definitionModules definition)
    mapM_ (verifyModule attributesVerification) (Map.elems indexedModules)
    verifyAttributes
        (definitionAttributes definition)
        (implicitIndexedModuleAsIndexedModule implicitIndexedModule)
        Set.empty
        attributesVerification
    return indexedModules
  where
    defaultModuleName = ModuleName "Default module"
    (moduleWithMetaSorts, sortNames) =
        indexedModuleWithMetaSorts defaultModuleName
    getIndexedModule (ImplicitIndexedModule im) = im
    defaultModuleWithMetaSorts = getIndexedModule moduleWithMetaSorts
    implicitModule = moduleMetaToKore uncheckedKoreModule
    nameToModule =
        Map.fromList
            (map (\m -> (moduleName m, m)) (definitionModules definition))
    implicitIndexedModuleAsIndexedModule im =
        case im of
            ImplicitIndexedModule m -> m


defaultAttributesVerification
    :: Either (Error VerifyError) AttributesVerification
defaultAttributesVerification = do
    modules <-
        verifyAndIndexDefinition
            DoNotVerifyAttributes uncheckedAttributesDefinition
    attributesModule <- case uncheckedAttributesDefinition of
        Definition { definitionModules = [ attributesModule ] } ->
            return attributesModule
        _ -> koreFail "Unexpected structure for the attributes definition."
    attributesIndexedModule <-
        case Map.lookup (moduleName attributesModule) modules of
            Just m  -> return m
            Nothing -> koreFail "Attributes module not indexed."
    return (VerifyAttributes attributesIndexedModule)

indexImplicitModules
    :: Either
        (Error VerifyError)
        ( Map.Map ModuleName KoreIndexedModule
        , KoreImplicitIndexedModule
        , Set.Set String
        )
indexImplicitModules = do
    defaultNames <- foldM verifyUniqueNames sortNames uncheckedKoreModules
    (indexedModules, defaultModule) <- foldM
        indexImplicitModule
        ( Map.singleton defaultModuleName defaultModuleWithMetaSorts
        , moduleWithMetaSorts
        )
        uncheckedKoreModules
    return (indexedModules, defaultModule, defaultNames)
  where
    defaultModuleName = ModuleName "Default module"
    getIndexedModule (ImplicitIndexedModule im) = im
    defaultModuleWithMetaSorts = getIndexedModule moduleWithMetaSorts
    (moduleWithMetaSorts, sortNames) =
        indexedModuleWithMetaSorts defaultModuleName

{-|'verifyKoreDefinition' is meant to be used only in the
'Data.Kore.Implicit' package. It verifies the correctness of a definition
containing only the 'kore' default module.
-}
verifyKoreDefinition
    :: AttributesVerification
    -> KoreDefinition
    -> Either (Error VerifyError) KoreIndexedModule
verifyKoreDefinition attributesVerification definition = do
    -- VerifyDefinition already checks the Kore module, so we skip it.
    modules <-
        verifyAndIndexDefinition
            attributesVerification
            definition { definitionModules = [] }
    m <-
        case definitionModules definition of
            [] ->
                koreFail
                    (  "The kore implicit definition should have exactly"
                    ++ " one module, but found none."
                    )
            [a] -> return a
            _ ->
                koreFail
                    (  "The kore implicit definition should have exactly"
                    ++ " one module, but found multiple ones."
                    )
    case Map.lookup (moduleName m) modules of
        Just a -> return a
        Nothing ->
            koreFail "Internal error: the implicit kore module was not indexed."
