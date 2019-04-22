{-|
Module      : Kore.Unification.Substitution
Description : The Substitution type.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
Stability   : experimental
Portability : portable
-}

module Kore.Unification.Substitution
    ( Substitution
    , unwrap
    , toMap
    , fromMap
    , wrap
    , modify
    , Kore.Unification.Substitution.mapVariables
    , isNormalized
    , null
    , variables
    , unsafeWrap
    , Kore.Unification.Substitution.filter
    , Kore.Unification.Substitution.freeVariables
    , partition
    ) where

import           Control.DeepSeq
                 ( NFData )
import qualified Data.Foldable as Foldable
import           Data.Hashable
import qualified Data.List as List
import           Data.Map.Strict
                 ( Map )
import qualified Data.Map.Strict as Map
import           Data.Set
                 ( Set )
import qualified Data.Set as Set
import           GHC.Generics
                 ( Generic )
import           Prelude hiding
                 ( null )

import Kore.Step.Pattern as Pattern
import Kore.TopBottom
       ( TopBottom (..) )

-- | 'Substitution' is a wrapper for a list of substitutions of the form
-- (variable level, StepPattern level variable). Values of this type should be
-- manipulated using the functions in this module.
data Substitution level variable
    -- TODO (thomas.tuegel): Instead of a sum type, use a product containing the
    -- normalized and denormalized parts of the substitution together. That
    -- would enable us to keep more substitutions normalized in the Semigroup
    -- instance below.
    = Substitution ![(variable level, StepPattern level variable)]
    | NormalizedSubstitution
        !(Map (variable level) (StepPattern level variable))
    deriving (Eq, Generic, Ord, Show)

instance NFData (variable level) => NFData (Substitution level variable)

instance
    Hashable (variable level) =>
    Hashable (Substitution level variable)
  where
    hashWithSalt salt (Substitution denorm) =
        salt `hashWithSalt` (0::Int) `hashWithSalt` denorm
    hashWithSalt salt (NormalizedSubstitution norm) =
        salt `hashWithSalt` (1::Int) `hashWithSalt` (Map.toList norm)

instance TopBottom (Substitution level variable)
  where
    isTop = null
    isBottom _ = False

instance Ord (variable level) => Semigroup (Substitution level variable) where
    a <> b
      | null a, null b = mempty
      | null a         = b
      | null b         = a
      | otherwise      = Substitution (unwrap a <> unwrap b)

instance Ord (variable level) => Monoid (Substitution level variable) where
    mempty = NormalizedSubstitution mempty

-- | Unwrap the 'Substitution' to its inner list of substitutions.
unwrap
    :: Substitution level variable
    -> [(variable level, StepPattern level variable)]
unwrap (Substitution xs) = xs
unwrap (NormalizedSubstitution xs)  = Map.toList xs

toMap
    :: Ord (variable level)
    => Substitution level variable
    -> Map (variable level) (StepPattern level variable)
toMap = Map.fromList . unwrap

fromMap
    :: Ord (variable level)
    => Map (variable level) (StepPattern level variable)
    -> Substitution level variable
fromMap = wrap . Map.toList

-- | Wrap the list of substitutions to an un-normalized substitution. Note that
-- @wrap . unwrap@ is not @id@ because the normalization state is lost.
wrap
    :: [(variable level, StepPattern level variable)]
    -> Substitution level variable
wrap [] = NormalizedSubstitution Map.empty
wrap xs = Substitution xs

-- | Wrap the list of substitutions to a normalized substitution. Do not use
-- this unless you are sure you need it.
unsafeWrap
    :: Ord (variable level)
    => [(variable level, StepPattern level variable)]
    -> Substitution level variable
unsafeWrap = NormalizedSubstitution . Map.fromList

-- | Maps a function over the inner representation of the 'Substitution'. The
-- normalization status is reset to un-normalized.
modify
    :: ( [(variable level, StepPattern level variable)]
        -> [(variable' level', StepPattern level' variable')]
       )
    -> Substitution level variable
    -> Substitution level' variable'
modify f = wrap . f . unwrap

-- | 'mapVariables' changes all the variables in the substitution
-- with the given function.
mapVariables
    ::  forall level variableFrom variableTo.
        Ord (variableTo level)
    => (variableFrom level -> variableTo level)
    -> Substitution level variableFrom
    -> Substitution level variableTo
mapVariables variableMapper =
    modify (map (mapVariable variableMapper))
  where
    mapVariable
        :: (variableFrom level -> variableTo level)
        -> (variableFrom level, StepPattern level variableFrom)
        -> (variableTo level, StepPattern level variableTo)
    mapVariable
        mapper
        (variable, patt)
      =
        (mapper variable, Pattern.mapVariables mapper patt)

-- | Returns true iff the substitution is normalized.
isNormalized :: Substitution level variable -> Bool
isNormalized (Substitution _)           = False
isNormalized (NormalizedSubstitution _) = True

-- | Returns true iff the substitution is empty.
null :: Substitution level variable -> Bool
null (Substitution denorm)         = List.null denorm
null (NormalizedSubstitution norm) = Map.null norm

-- | Returns the list of variables in the 'Substitution'.
variables :: Substitution level variable -> [(variable level)]
variables = fmap fst . unwrap

-- | Filter the variables of the 'Substitution'.
filter
    :: (variable level -> Bool)
    -> Substitution level variable
    -> Substitution level variable
filter filtering =
    modify (Prelude.filter (filtering . fst))

partition
    :: (variable level -> StepPattern level variable -> Bool)
    -> Substitution level variable
    -> (Substitution level variable, Substitution level variable)
partition criterion (Substitution substitution) =
    let (true, false) = List.partition (uncurry criterion) substitution
    in (Substitution true, Substitution false)
partition criterion (NormalizedSubstitution substitution) =
    let (true, false) = Map.partitionWithKey criterion substitution
    in (NormalizedSubstitution true, NormalizedSubstitution false)

{- | Return the free variables of the 'Substitution'.

In a substitution of the form
@
variable = term
@
the free variables are @variable@ and all the free variables of @term@.

 -}
freeVariables
    :: Ord (variable level)
    => Substitution level variable
    -> Set (variable level)
freeVariables = Foldable.foldl' freeVariablesWorker Set.empty . unwrap
  where
    freeVariablesWorker freeVars (x, t) =
        freeVars <> Set.insert x (Pattern.freeVariables t)
