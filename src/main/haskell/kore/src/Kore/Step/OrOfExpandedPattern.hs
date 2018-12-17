{-|
Module      : Kore.Step.OrOfExpandedPattern
Description : Data structures and functions for manipulating
              OrOfExpandedPatterns, which occur naturally during
              pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.OrOfExpandedPattern
    ( CommonOrOfExpandedPattern
    , MultiOr (..)
    , OrOfExpandedPattern
    , OrOfPredicateSubstitution
    , filterOr -- TODO: This should be internal-only.
    , flatten
    , fmapFlattenWithPairs
    , fmapWithPairs
    , fullCrossProduct
    , isFalse
    , isTrue
    , make
    , makeFromSinglePurePattern
    , merge
    , crossProductGeneric
    , crossProductGenericF
    , extractPatterns
    , toExpandedPattern
    , traverseWithPairs
    , traverseFlattenWithPairs
    , traverseFlattenWithPairsGeneric
    ) where

import           Data.List
                 ( foldl' )
import           Data.Reflection
                 ( Given )
import qualified Data.Set as Set

import           Kore.AST.Common
                 ( SortedVariable, Variable )
import           Kore.AST.MetaOrObject
import           Kore.ASTUtils.SmartConstructors
                 ( mkOr )
import           Kore.IndexedModule.MetadataTools
                 ( SymbolOrAliasSorts )
import           Kore.Predicate.Predicate
                 ( makeTruePredicate )
import           Kore.Step.ExpandedPattern
                 ( ExpandedPattern, Predicated (..) )
import qualified Kore.Step.ExpandedPattern as ExpandedPattern
import           Kore.Step.Pattern

{-| 'MultiOr' is a Matching logic or of its children

TODO(virgil): Make this a list-like monad, many things would be nicer.
-}
newtype MultiOr child = MultiOr [child]
    deriving (Applicative, Eq, Foldable, Functor, Monad, Show, Traversable)

type OrOfPredicated level variable term =
    MultiOr (Predicated level variable term)

{-| 'OrOfExpandedPattern' is a 'MultiOr' of 'ExpandedPatterns', which is the
most common case.
-}
type OrOfExpandedPattern level variable
    = OrOfPredicated level variable (StepPattern level variable)

{-| 'OrOfPredicateSubstitution' is a 'MultiOr' of 'PredicateSubstitution'.
-}
type OrOfPredicateSubstitution level variable
    = OrOfPredicated level variable ()

{-| 'CommonOrOfExpandedPattern' particularizes 'OrOfExpandedPattern' to
'Variable', following the same convention as the other Common* types.
-}
type CommonOrOfExpandedPattern level = OrOfExpandedPattern level Variable

{-| 'OrBool' is an some sort of Bool data type used when evaluating things
inside an 'MultiOr'.
-}
data OrBool = OrTrue | OrFalse | OrUnknown

{- | Simplify the disjunction of patterns.

The arguments are simplified by filtering on @\\top@ and @\\bottom@. The
idempotency property of disjunction (@\\or(φ,φ)=φ@) is applied to remove
duplicated patterns from the result.

See also: 'filterUnique'

 -}
filterOr
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    => OrOfPredicated level variable term
    -> OrOfPredicated level variable term
filterOr =
    filterGeneric patternToOrBool . filterUnique

{- | Simplify the disjunction by eliminating duplicate elements.

The idempotency property of disjunction (@\\or(φ,φ)=φ@) is applied to remove
duplicated patterns from the result.

Note: The patterns are only compared for literal syntactic equality. Filtering
does not account for α-equivalence, so patterns containing @\\forall@ and
@\\exists@ may be considered inequal although they are equivalent in the
matching logic sense.

 -}
filterUnique :: Ord a => MultiOr a -> MultiOr a
filterUnique = MultiOr . Set.toList . Set.fromList . extract

{-| 'make' constructs a normalized 'OrOfPredicated'.
 -}
make
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    => [Predicated level variable term]
    -> OrOfPredicated level variable term
make patts = filterOr (MultiOr patts)

{-|'makeMultiOr' constructs a 'MultiOr'.
-}
makeMultiOr :: [a] -> MultiOr a
makeMultiOr = MultiOr

{-|'makeFromPurePattern' constructs a normalized 'OrOfExpandedPattern' from
'StepPatterns'.
-}
makeFromSinglePurePattern
    :: (MetaOrObject level, Ord (variable level))
    => StepPattern level variable
    -> OrOfExpandedPattern level variable
makeFromSinglePurePattern patt = make [ ExpandedPattern.fromPurePattern patt ]

{-| 'extractPatterns' particularizes 'extract' to ExpandedPattern.

It returns the patterns inside an 'or'.
-}
extractPatterns
    :: OrOfPredicated level variable term -> [Predicated level variable term]
extractPatterns = extract

{-| 'extract' returns the patterns inside an 'or'.
-}
extract :: MultiOr a -> [a]
extract (MultiOr x) = x

{-| 'isFalse' checks if the 'Or' is composed only of bottom patterns.
-}
isFalse
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    => OrOfPredicated level variable term
    -> Bool
isFalse patt =
    case filterOr patt of
        MultiOr [] -> True
        _ -> False

{-| 'isTrue' checks if the 'Or' is composed of a single top pattern.

Assumes that the pattern was filtered.
-}
isTrue
    :: ExpandedPattern.TopBottomTerm term
    =>  OrOfPredicated level variable term -> Bool
isTrue (MultiOr [ predicated ]) = ExpandedPattern.isTop predicated
isTrue _ = False

{-| 'fullCrossProduct' distributes all the elements in a list of or, making
all possible tuples. Each of these tuples will be an element of the resulting
or. This is useful when, say, distributing 'And' or 'Application' patterns
over 'Or'.

As an example,

@
fullCrossProduct
    [ make [a1, a2]
    , make [b1, b2]
    , make [c1, c2]
    ]
@

will produce something equivalent to

@
makeGeneric
    [ [a1, b1, c1]
    , [a1, b1, c2]
    , [a1, b2, c1]
    , [a1, b2, c2]
    , [a2, b1, c1]
    , [a2, b1, c2]
    , [a2, b2, c1]
    , [a2, b2, c2]
    ]
@

-}
fullCrossProduct
    :: [OrOfPredicated level variable term]
    -> MultiOr [Predicated level variable term]
fullCrossProduct [] = makeMultiOr [[]]
fullCrossProduct ors =
    foldr (crossProductGeneric (:)) lastOrsWithLists (init ors)
  where
    lastOrsWithLists = fmap (: []) (last ors)

{-| 'flatten' transforms a MultiOr (OrOfPredicated level variable)
into an OrOfPredicated by or-ing all the inner elements.
-}
flatten
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    => MultiOr (OrOfPredicated level variable term)
    -> OrOfPredicated level variable term
flatten ors =
    filterOr (flattenGeneric ors)

{-| 'patternToOrBool' does a very simple attempt to check whether a pattern
is top or bottom.
-}
patternToOrBool
    :: ExpandedPattern.TopBottomTerm term
    => Predicated level variable term -> OrBool
patternToOrBool patt
  | ExpandedPattern.isTop patt = OrTrue
  | ExpandedPattern.isBottom patt = OrFalse
  | otherwise = OrUnknown

{-| fmaps an or in a similar way to traverseWithPairs.
-}
fmapWithPairs
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    =>  (  Predicated level variable term
        -> (Predicated level variable term, a)
        )
    -> OrOfPredicated level variable term
    -> (OrOfPredicated level variable term, [a])
fmapWithPairs mapper patt =
    (filterOr (fmap fst mapped), extract (fmap snd mapped))
  where
    mapped = fmap mapper patt

{-| 'traverseWithPairs' traverses an or with a function that returns a
(pattern, something) pair, then returns a 'MultiOr' of the patterns and
a list of that something.

This is handy when one transforms the patterns in an 'or', also producing
proofs for each transformation: this function will return the transformed or
and a list of the proofs involved in the transformation.
-}
traverseWithPairs
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Monad f
        , Ord (variable level)
        , Ord term
        )
    =>  (  Predicated level variable term
        -> f (Predicated level variable term, a)
        )
    -> OrOfPredicated level variable term
    -> f (OrOfPredicated level variable term, [a])
traverseWithPairs mapper patt = do
    mapped <- traverse mapper patt
    return (filterOr (fmap fst mapped), extract (fmap snd mapped))

{-| 'fmapFlattenWithPairs' fmaps an or in a similar way to
'traverseFlattenWithPairs'.
-}
fmapFlattenWithPairs
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    =>  (  Predicated level variable term
        -> (OrOfPredicated level variable term, a)
        )
    -> OrOfPredicated level variable term
    -> (OrOfPredicated level variable term, [a])
fmapFlattenWithPairs mapper patt =
    (flatten (fmap fst mapped), extract (fmap snd mapped))
  where
    mapped = fmap mapper patt

{-| 'traverseFlattenWithPairs' is similar to 'traverseWithPairs', except
that its function returns an 'OrOfPredicated', so the actual result
is flattened at the end.
-}
traverseFlattenWithPairs
    ::  ( ExpandedPattern.TopBottomTerm term
        , Monad f
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    =>  (  Predicated level variable term
        -> f (OrOfPredicated level variable term, a)
        )
    -> OrOfPredicated level variable term
    -> f (OrOfPredicated level variable term, [a])
traverseFlattenWithPairs mapper patt = do
    mapped <- traverse mapper patt
    return (flatten (fmap fst mapped), extract (fmap snd mapped))

{-| 'traverseFlattenWithPairsGeneric' is similar to 'traverseFlattenWithPairs',
except that it works with 'MultiOr's.
-}
traverseFlattenWithPairsGeneric
    ::  ( ExpandedPattern.TopBottomTerm term
        , Monad f
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    =>  (  a
        -> f (OrOfPredicated level variable term, pair)
        )
    -> MultiOr a
    -> f (OrOfPredicated level variable term, [pair])
traverseFlattenWithPairsGeneric mapper patt = do
    mapped <- traverse mapper patt
    return (flatten (fmap fst mapped), extract (fmap snd mapped))

{-| 'filterGeneric' simplifies a MultiOr according to a function which
evaluates its children to true/false/unknown.
-}
filterGeneric
    :: (child -> OrBool)
    -> MultiOr child
    -> MultiOr child
filterGeneric orFilter (MultiOr patts) =
    go orFilter [] patts
  where
    go  :: (child -> OrBool)
        -> [child]
        -> [child]
        -> MultiOr child
    go _ filtered [] = MultiOr (reverse filtered)
    go filterOr' filtered (element:unfiltered) =
        case filterOr' element of
            OrTrue -> MultiOr [element]
            OrFalse -> go filterOr' filtered unfiltered
            OrUnknown -> go filterOr' (element:filtered) unfiltered

{-| 'crossProductGeneric' makes all pairs between the elements of two ors,
then applies the given function to the result.

As an example,

@
crossProductGeneric
    f
    (make [a1, a2])
    (make [b1, b2])
    ]
@

will produce something equivalent to

@
makeGeneric
    [ f(a1, b1)
    , f(a1, b2)
    , f(a2, b1)
    , f(a2, b2)
    ]
@

-}
crossProductGeneric
    :: (child1 -> child2 -> child3)
    -> MultiOr child1
    -> MultiOr child2
    -> MultiOr child3
crossProductGeneric joiner (MultiOr first) (MultiOr second) =
    MultiOr $ joiner <$> first <*> second

{-| 'crossProductGenericF' is the same as 'crossProductGeneric' except that it
works under an applicative thing.
-}
crossProductGenericF
    :: Applicative f
    => (child1 -> child2 -> f child3)
    -> MultiOr child1
    -> MultiOr child2
    -> f (MultiOr child3)
crossProductGenericF joiner (MultiOr first) (MultiOr second) =
    MultiOr <$> sequenceA (joiner <$> first <*> second)

{- | Merge two disjunctions of patterns.

The arguments are simplified by filtering on @\\top@ and @\\bottom@. The
idempotency property of disjunction (@\\or(φ,φ)=φ@) is applied to remove
duplicated patterns from the result.

Note: The patterns are only compared for literal syntactic equality. Filtering
does not account for α-equivalence, so patterns containing @\\forall@ and
@\\exists@ may be considered inequal although they are equivalent in the
matching logic sense.

See also: 'filterOr'

 -}
merge
    ::  ( ExpandedPattern.TopBottomTerm term
        , MetaOrObject level
        , Ord (variable level)
        , Ord term
        )
    => OrOfPredicated level variable term
    -> OrOfPredicated level variable term
    -> OrOfPredicated level variable term
merge patts1 patts2 =
    filterOr (mergeGeneric patts1 patts2)

{-| 'merge' merges two 'MultiOr'.
-}
mergeGeneric
    :: MultiOr child
    -> MultiOr child
    -> MultiOr child
-- TODO(virgil): All *Generic functions should also receive a filter,
-- otherwise we could have unexpected results when a caller uses the generic
-- version but produces a result with ExpandedPatterns.
mergeGeneric (MultiOr patts1) (MultiOr patts2) =
    MultiOr (patts1 ++ patts2)

{-| 'flattenGeneric' merges all 'MultiOr's inside a 'MultiOr'.
-}
flattenGeneric
    :: MultiOr (MultiOr child)
    -> MultiOr child
flattenGeneric (MultiOr []) = MultiOr []
flattenGeneric (MultiOr ors) = foldr1 mergeGeneric ors

{-| 'toExpandedPattern' transforms an 'OrOfExpandedPattern' into
an 'ExpandedPattern'.
-}
toExpandedPattern
    ::  ( MetaOrObject level
        , Given (SymbolOrAliasSorts level)
        , SortedVariable variable
        , Eq (variable level)
        , Show (variable level)
        )
    => OrOfExpandedPattern level variable -> ExpandedPattern level variable
toExpandedPattern (MultiOr []) = ExpandedPattern.bottom
toExpandedPattern (MultiOr [patt]) = patt
toExpandedPattern (MultiOr patts) =
    case map ExpandedPattern.toMLPattern patts of
        [] -> error "Not expecting empty pattern list."
        (p : ps) ->
            Predicated
                { term = foldl' mkOr p ps
                , predicate = makeTruePredicate
                , substitution = mempty
                }
