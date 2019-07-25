{-|
Module      : Kore.ASTHelpers
Description : Utilities for handling ASTs.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable

Each time a function is added to this file, one should consider putting it in a
more specific file. Also, one should consider extracting groups of functions in
more specific files.
-}
module Kore.ASTHelpers
    ( quantifyFreeVariables
    ) where

import           Control.Comonad.Trans.Cofree
                 ( CofreeF (..) )
import           Data.Foldable
                 ( foldl' )
import qualified Data.Map as Map
import qualified Data.Set as Set
import           Data.Text
                 ( Text )

import qualified Kore.Attribute.Null as Attribute
import           Kore.SubstVar
                 ( SubstVar (..) )
import qualified Kore.SubstVar as SubstVar
import           Kore.Syntax hiding
                 ( substituteSortVariables )
import           Kore.Unparser
import           Kore.Variables.Free


{-|'quantifyFreeVariables' quantifies all free variables in the given pattern.
It assumes that the pattern has the provided sort.
-}
quantifyFreeVariables
    :: Sort
    -> Pattern Variable Attribute.Null
    -> Pattern Variable Attribute.Null
quantifyFreeVariables s p =
    foldl'
        (wrapAndQuantify s)
        p
        (checkUnique (freePureVariables p))

wrapAndQuantify
    :: Sort
    -> Pattern Variable Attribute.Null
    -> SubstVar Variable
    -> Pattern Variable Attribute.Null
wrapAndQuantify s p (RegVar var) =
    asPattern
        (mempty :< ForallF Forall
            { forallSort = s
            , forallVariable = var
            , forallChild = p
            }
        )
wrapAndQuantify _ _ (SetVar var) =
    error ("Cannot quantify set variable " ++ unparseToString var)

checkUnique
    :: Set.Set (SubstVar Variable) -> Set.Set (SubstVar Variable)
checkUnique variables =
    case checkUniqueEither (Set.toList variables) Map.empty of
        Right _  -> variables
        Left err -> error err

checkUniqueEither
    :: [SubstVar Variable]
    -> Map.Map Text (SubstVar Variable)
    -> Either String ()
checkUniqueEither [] _ = Right ()
checkUniqueEither (var:vars) indexed =
    case Map.lookup name indexed of
        Nothing -> checkUniqueEither vars (Map.insert name var indexed)
        Just existingV ->
            Left
                (  "Conflicting variables: "
                ++ show var
                ++ " and "
                ++ show existingV
                ++ "."
                )
  where
    name = getId . variableName . SubstVar.asVariable $ var
