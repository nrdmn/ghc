%
% (c) The University of Glasgow 2006
% (c) The University of Glasgow 1992-2002
%

\begin{code}
-- | Highly random utility functions
module Util (
        -- * Flags dependent on the compiler build
        ghciSupported, debugIsOn, ghciTablesNextToCode, isDynamicGhcLib,
        isWindowsHost, isWindowsTarget, isDarwinTarget,

        -- * General list processing
        zipEqual, zipWithEqual, zipWith3Equal, zipWith4Equal,
        zipLazy, stretchZipWith,
        
        unzipWith,
        
        mapFst, mapSnd,
        mapAndUnzip, mapAndUnzip3,
        nOfThem, filterOut, partitionWith, splitEithers,
        
        foldl1', foldl2, count, all2,

        lengthExceeds, lengthIs, lengthAtLeast,
        listLengthCmp, atLength, equalLength, compareLength,

        isSingleton, only, singleton,
        notNull, snocView,

        isIn, isn'tIn,

        -- * Tuples
        fstOf3, sndOf3, thirdOf3,

        -- * List operations controlled by another list
        takeList, dropList, splitAtList, split,
        dropTail,

        -- * For loop
        nTimes,

        -- * Sorting
        sortLe, sortWith, on,

        -- * Comparisons
        isEqual, eqListBy,
        thenCmp, cmpList,
        removeSpaces,

        -- * Transitive closures
        transitiveClosure,

        -- * Strictness
        seqList,

        -- * Module names
        looksLikeModuleName,

        -- * Argument processing
        getCmd, toCmdArgs, toArgs,

        -- * Floating point
        readRational,

        -- * IO-ish utilities
        createDirectoryHierarchy,
        doesDirNameExist,
        modificationTimeIfExists,

        global, consIORef, globalMVar, globalEmptyMVar,

        -- * Filenames and paths
        Suffix,
        splitLongestPrefix,
        escapeSpaces,
        parseSearchPath,
        Direction(..), reslash,

        -- * Utils for defining Data instances
        abstractConstr, abstractDataType, mkNoRepType
    ) where

#include "HsVersions.h"

import Panic

import Data.Data
import Data.IORef       ( IORef, newIORef, atomicModifyIORef )
import System.IO.Unsafe ( unsafePerformIO )
import Data.List        hiding (group)
import Control.Concurrent.MVar ( MVar, newMVar, newEmptyMVar )

#ifdef DEBUG
import FastTypes
#endif

import Control.Monad    ( unless )
import System.IO.Error as IO ( catch, isDoesNotExistError )
import System.Directory ( doesDirectoryExist, createDirectory,
                          getModificationTime )
import System.FilePath
import Data.Char        ( isUpper, isAlphaNum, isSpace, ord, isDigit )
import Data.Ratio       ( (%) )
import System.Time      ( ClockTime )

infixr 9 `thenCmp`
\end{code}

%************************************************************************
%*                                                                      *
\subsection{Is DEBUG on, are we on Windows, etc?}
%*                                                                      *
%************************************************************************

These booleans are global constants, set by CPP flags.  They allow us to
recompile a single module (this one) to change whether or not debug output
appears. They sometimes let us avoid even running CPP elsewhere.

It's important that the flags are literal constants (True/False). Then,
with -0, tests of the flags in other modules will simplify to the correct
branch of the conditional, thereby dropping debug code altogether when
the flags are off.

\begin{code}
ghciSupported :: Bool
#ifdef GHCI
ghciSupported = True
#else
ghciSupported = False
#endif

debugIsOn :: Bool
#ifdef DEBUG
debugIsOn = True
#else
debugIsOn = False
#endif

ghciTablesNextToCode :: Bool
#ifdef GHCI_TABLES_NEXT_TO_CODE
ghciTablesNextToCode = True
#else
ghciTablesNextToCode = False
#endif

isDynamicGhcLib :: Bool
#ifdef DYNAMIC
isDynamicGhcLib = True
#else
isDynamicGhcLib = False
#endif

isWindowsHost :: Bool
#ifdef mingw32_HOST_OS
isWindowsHost = True
#else
isWindowsHost = False
#endif

isWindowsTarget :: Bool
#ifdef mingw32_TARGET_OS
isWindowsTarget = True
#else
isWindowsTarget = False
#endif

isDarwinTarget :: Bool
#ifdef darwin_TARGET_OS
isDarwinTarget = True
#else
isDarwinTarget = False
#endif
\end{code}

%************************************************************************
%*                                                                      *
\subsection{A for loop}
%*                                                                      *
%************************************************************************

\begin{code}
-- | Compose a function with itself n times.  (nth rather than twice)
nTimes :: Int -> (a -> a) -> (a -> a)
nTimes 0 _ = id
nTimes 1 f = f
nTimes n f = f . nTimes (n-1) f
\end{code}

\begin{code}
fstOf3   :: (a,b,c) -> a    
sndOf3   :: (a,b,c) -> b    
thirdOf3 :: (a,b,c) -> c    
fstOf3      (a,_,_) =  a
sndOf3      (_,b,_) =  b
thirdOf3    (_,_,c) =  c
\end{code}

%************************************************************************
%*                                                                      *
\subsection[Utils-lists]{General list processing}
%*                                                                      *
%************************************************************************

\begin{code}
filterOut :: (a->Bool) -> [a] -> [a]
-- ^ Like filter, only it reverses the sense of the test
filterOut _ [] = []
filterOut p (x:xs) | p x       = filterOut p xs
                   | otherwise = x : filterOut p xs

partitionWith :: (a -> Either b c) -> [a] -> ([b], [c])
-- ^ Uses a function to determine which of two output lists an input element should join
partitionWith _ [] = ([],[])
partitionWith f (x:xs) = case f x of
                         Left  b -> (b:bs, cs)
                         Right c -> (bs, c:cs)
    where (bs,cs) = partitionWith f xs

splitEithers :: [Either a b] -> ([a], [b])
-- ^ Teases a list of 'Either's apart into two lists
splitEithers [] = ([],[])
splitEithers (e : es) = case e of
                        Left x -> (x:xs, ys)
                        Right y -> (xs, y:ys)
    where (xs,ys) = splitEithers es
\end{code}

A paranoid @zip@ (and some @zipWith@ friends) that checks the lists
are of equal length.  Alastair Reid thinks this should only happen if
DEBUGging on; hey, why not?

\begin{code}
zipEqual        :: String -> [a] -> [b] -> [(a,b)]
zipWithEqual    :: String -> (a->b->c) -> [a]->[b]->[c]
zipWith3Equal   :: String -> (a->b->c->d) -> [a]->[b]->[c]->[d]
zipWith4Equal   :: String -> (a->b->c->d->e) -> [a]->[b]->[c]->[d]->[e]

#ifndef DEBUG
zipEqual      _ = zip
zipWithEqual  _ = zipWith
zipWith3Equal _ = zipWith3
zipWith4Equal _ = zipWith4
#else
zipEqual _   []     []     = []
zipEqual msg (a:as) (b:bs) = (a,b) : zipEqual msg as bs
zipEqual msg _      _      = panic ("zipEqual: unequal lists:"++msg)

zipWithEqual msg z (a:as) (b:bs)=  z a b : zipWithEqual msg z as bs
zipWithEqual _   _ [] []        =  []
zipWithEqual msg _ _ _          =  panic ("zipWithEqual: unequal lists:"++msg)

zipWith3Equal msg z (a:as) (b:bs) (c:cs)
                                =  z a b c : zipWith3Equal msg z as bs cs
zipWith3Equal _   _ [] []  []   =  []
zipWith3Equal msg _ _  _   _    =  panic ("zipWith3Equal: unequal lists:"++msg)

zipWith4Equal msg z (a:as) (b:bs) (c:cs) (d:ds)
                                =  z a b c d : zipWith4Equal msg z as bs cs ds
zipWith4Equal _   _ [] [] [] [] =  []
zipWith4Equal msg _ _  _  _  _  =  panic ("zipWith4Equal: unequal lists:"++msg)
#endif
\end{code}

\begin{code}
-- | 'zipLazy' is a kind of 'zip' that is lazy in the second list (observe the ~)
zipLazy :: [a] -> [b] -> [(a,b)]
zipLazy []     _       = []
-- We want to write this, but with GHC 6.4 we get a warning, so it
-- doesn't validate:
-- zipLazy (x:xs) ~(y:ys) = (x,y) : zipLazy xs ys
-- so we write this instead:
zipLazy (x:xs) zs = let y : ys = zs
                    in (x,y) : zipLazy xs ys
\end{code}


\begin{code}
stretchZipWith :: (a -> Bool) -> b -> (a->b->c) -> [a] -> [b] -> [c]
-- ^ @stretchZipWith p z f xs ys@ stretches @ys@ by inserting @z@ in
-- the places where @p@ returns @True@

stretchZipWith _ _ _ []     _ = []
stretchZipWith p z f (x:xs) ys
  | p x       = f x z : stretchZipWith p z f xs ys
  | otherwise = case ys of
                []     -> []
                (y:ys) -> f x y : stretchZipWith p z f xs ys
\end{code}


\begin{code}
mapFst :: (a->c) -> [(a,b)] -> [(c,b)]
mapSnd :: (b->c) -> [(a,b)] -> [(a,c)]

mapFst f xys = [(f x, y) | (x,y) <- xys]
mapSnd f xys = [(x, f y) | (x,y) <- xys]

mapAndUnzip :: (a -> (b, c)) -> [a] -> ([b], [c])

mapAndUnzip _ [] = ([], [])
mapAndUnzip f (x:xs)
  = let (r1,  r2)  = f x
        (rs1, rs2) = mapAndUnzip f xs
    in
    (r1:rs1, r2:rs2)

mapAndUnzip3 :: (a -> (b, c, d)) -> [a] -> ([b], [c], [d])

mapAndUnzip3 _ [] = ([], [], [])
mapAndUnzip3 f (x:xs)
  = let (r1,  r2,  r3)  = f x
        (rs1, rs2, rs3) = mapAndUnzip3 f xs
    in
    (r1:rs1, r2:rs2, r3:rs3)
\end{code}

\begin{code}
nOfThem :: Int -> a -> [a]
nOfThem n thing = replicate n thing

-- | @atLength atLen atEnd ls n@ unravels list @ls@ to position @n@. Precisely:
--
-- @
--  atLength atLenPred atEndPred ls n
--   | n < 0         = atLenPred n
--   | length ls < n = atEndPred (n - length ls)
--   | otherwise     = atLenPred (drop n ls)
-- @
atLength :: ([a] -> b)
         -> (Int -> b)
         -> [a]
         -> Int
         -> b
atLength atLenPred atEndPred ls n
  | n < 0     = atEndPred n
  | otherwise = go n ls
  where
    go n [] = atEndPred n
    go 0 ls = atLenPred ls
    go n (_:xs) = go (n-1) xs

-- Some special cases of atLength:

lengthExceeds :: [a] -> Int -> Bool
-- ^ > (lengthExceeds xs n) = (length xs > n)
lengthExceeds = atLength notNull (const False)

lengthAtLeast :: [a] -> Int -> Bool
lengthAtLeast = atLength notNull (== 0)

lengthIs :: [a] -> Int -> Bool
lengthIs = atLength null (==0)

listLengthCmp :: [a] -> Int -> Ordering
listLengthCmp = atLength atLen atEnd
 where
  atEnd 0      = EQ
  atEnd x
   | x > 0     = LT -- not yet seen 'n' elts, so list length is < n.
   | otherwise = GT

  atLen []     = EQ
  atLen _      = GT

equalLength :: [a] -> [b] -> Bool
equalLength []     []     = True
equalLength (_:xs) (_:ys) = equalLength xs ys
equalLength _      _      = False

compareLength :: [a] -> [b] -> Ordering
compareLength []     []     = EQ
compareLength (_:xs) (_:ys) = compareLength xs ys
compareLength []     _      = LT
compareLength _      []     = GT

----------------------------
singleton :: a -> [a]
singleton x = [x]

isSingleton :: [a] -> Bool
isSingleton [_] = True
isSingleton _   = False

notNull :: [a] -> Bool
notNull [] = False
notNull _  = True

only :: [a] -> a
#ifdef DEBUG
only [a] = a
#else
only (a:_) = a
#endif
only _ = panic "Util: only"
\end{code}

Debugging/specialising versions of \tr{elem} and \tr{notElem}

\begin{code}
isIn, isn'tIn :: Eq a => String -> a -> [a] -> Bool

# ifndef DEBUG
isIn    _msg x ys = x `elem` ys
isn'tIn _msg x ys = x `notElem` ys

# else /* DEBUG */
isIn msg x ys
  = elem100 (_ILIT(0)) x ys
  where
    elem100 _ _ []        = False
    elem100 i x (y:ys)
      | i ># _ILIT(100) = trace ("Over-long elem in " ++ msg)
                                (x `elem` (y:ys))
      | otherwise       = x == y || elem100 (i +# _ILIT(1)) x ys

isn'tIn msg x ys
  = notElem100 (_ILIT(0)) x ys
  where
    notElem100 _ _ [] =  True
    notElem100 i x (y:ys)
      | i ># _ILIT(100) = trace ("Over-long notElem in " ++ msg)
                                (x `notElem` (y:ys))
      | otherwise      =  x /= y && notElem100 (i +# _ILIT(1)) x ys
# endif /* DEBUG */
\end{code}

%************************************************************************
%*                                                                      *
\subsubsection[Utils-Carsten-mergesort]{A mergesort from Carsten}
%*                                                                      *
%************************************************************************

\begin{display}
Date: Mon, 3 May 93 20:45:23 +0200
From: Carsten Kehler Holst <kehler@cs.chalmers.se>
To: partain@dcs.gla.ac.uk
Subject: natural merge sort beats quick sort [ and it is prettier ]

Here is a piece of Haskell code that I'm rather fond of. See it as an
attempt to get rid of the ridiculous quick-sort routine. group is
quite useful by itself I think it was John's idea originally though I
believe the lazy version is due to me [surprisingly complicated].
gamma [used to be called] is called gamma because I got inspired by
the Gamma calculus. It is not very close to the calculus but does
behave less sequentially than both foldr and foldl. One could imagine
a version of gamma that took a unit element as well thereby avoiding
the problem with empty lists.

I've tried this code against

   1) insertion sort - as provided by haskell
   2) the normal implementation of quick sort
   3) a deforested version of quick sort due to Jan Sparud
   4) a super-optimized-quick-sort of Lennart's

If the list is partially sorted both merge sort and in particular
natural merge sort wins. If the list is random [ average length of
rising subsequences = approx 2 ] mergesort still wins and natural
merge sort is marginally beaten by Lennart's soqs. The space
consumption of merge sort is a bit worse than Lennart's quick sort
approx a factor of 2. And a lot worse if Sparud's bug-fix [see his
fpca article ] isn't used because of group.

have fun
Carsten
\end{display}

\begin{code}
group :: (a -> a -> Bool) -> [a] -> [[a]]
-- Given a <= function, group finds maximal contiguous up-runs
-- or down-runs in the input list.
-- It's stable, in the sense that it never re-orders equal elements
--
-- Date: Mon, 12 Feb 1996 15:09:41 +0000
-- From: Andy Gill <andy@dcs.gla.ac.uk>
-- Here is a `better' definition of group.

group _ []     = []
group p (x:xs) = group' xs x x (x :)
  where
    group' []     _     _     s  = [s []]
    group' (x:xs) x_min x_max s
        |      x_max `p` x  = group' xs x_min x     (s . (x :))
        | not (x_min `p` x) = group' xs x     x_max ((x :) . s)
        | otherwise         = s [] : group' xs x x (x :)
        -- NB: the 'not' is essential for stablity
        --     x `p` x_min would reverse equal elements

generalMerge :: (a -> a -> Bool) -> [a] -> [a] -> [a]
generalMerge _ xs [] = xs
generalMerge _ [] ys = ys
generalMerge p (x:xs) (y:ys) | x `p` y   = x : generalMerge p xs     (y:ys)
                             | otherwise = y : generalMerge p (x:xs) ys

-- gamma is now called balancedFold

balancedFold :: (a -> a -> a) -> [a] -> a
balancedFold _ [] = error "can't reduce an empty list using balancedFold"
balancedFold _ [x] = x
balancedFold f l  = balancedFold f (balancedFold' f l)

balancedFold' :: (a -> a -> a) -> [a] -> [a]
balancedFold' f (x:y:xs) = f x y : balancedFold' f xs
balancedFold' _ xs = xs

generalNaturalMergeSort :: (a -> a -> Bool) -> [a] -> [a]
generalNaturalMergeSort _ [] = []
generalNaturalMergeSort p xs = (balancedFold (generalMerge p) . group p) xs

#if NOT_USED
generalMergeSort p [] = []
generalMergeSort p xs = (balancedFold (generalMerge p) . map (: [])) xs

mergeSort, naturalMergeSort :: Ord a => [a] -> [a]

mergeSort = generalMergeSort (<=)
naturalMergeSort = generalNaturalMergeSort (<=)

mergeSortLe le = generalMergeSort le
#endif

sortLe :: (a->a->Bool) -> [a] -> [a]
sortLe le = generalNaturalMergeSort le

sortWith :: Ord b => (a->b) -> [a] -> [a]
sortWith get_key xs = sortLe le xs
  where
    x `le` y = get_key x < get_key y

on :: (a -> a -> c) -> (b -> a) -> b -> b -> c
on cmp sel = \x y -> sel x `cmp` sel y

\end{code}

%************************************************************************
%*                                                                      *
\subsection[Utils-transitive-closure]{Transitive closure}
%*                                                                      *
%************************************************************************

This algorithm for transitive closure is straightforward, albeit quadratic.

\begin{code}
transitiveClosure :: (a -> [a])         -- Successor function
                  -> (a -> a -> Bool)   -- Equality predicate
                  -> [a]
                  -> [a]                -- The transitive closure

transitiveClosure succ eq xs
 = go [] xs
 where
   go done []                      = done
   go done (x:xs) | x `is_in` done = go done xs
                  | otherwise      = go (x:done) (succ x ++ xs)

   _ `is_in` []                 = False
   x `is_in` (y:ys) | eq x y    = True
                    | otherwise = x `is_in` ys
\end{code}

%************************************************************************
%*                                                                      *
\subsection[Utils-accum]{Accumulating}
%*                                                                      *
%************************************************************************

A combination of foldl with zip.  It works with equal length lists.

\begin{code}
foldl2 :: (acc -> a -> b -> acc) -> acc -> [a] -> [b] -> acc
foldl2 _ z [] [] = z
foldl2 k z (a:as) (b:bs) = foldl2 k (k z a b) as bs
foldl2 _ _ _      _      = panic "Util: foldl2"

all2 :: (a -> b -> Bool) -> [a] -> [b] -> Bool
-- True if the lists are the same length, and
-- all corresponding elements satisfy the predicate
all2 _ []     []     = True
all2 p (x:xs) (y:ys) = p x y && all2 p xs ys
all2 _ _      _      = False
\end{code}

Count the number of times a predicate is true

\begin{code}
count :: (a -> Bool) -> [a] -> Int
count _ [] = 0
count p (x:xs) | p x       = 1 + count p xs
               | otherwise = count p xs
\end{code}

@splitAt@, @take@, and @drop@ but with length of another
list giving the break-off point:

\begin{code}
takeList :: [b] -> [a] -> [a]
takeList [] _ = []
takeList (_:xs) ls =
   case ls of
     [] -> []
     (y:ys) -> y : takeList xs ys

dropList :: [b] -> [a] -> [a]
dropList [] xs    = xs
dropList _  xs@[] = xs
dropList (_:xs) (_:ys) = dropList xs ys


splitAtList :: [b] -> [a] -> ([a], [a])
splitAtList [] xs     = ([], xs)
splitAtList _ xs@[]   = (xs, xs)
splitAtList (_:xs) (y:ys) = (y:ys', ys'')
    where
      (ys', ys'') = splitAtList xs ys

-- drop from the end of a list
dropTail :: Int -> [a] -> [a]
dropTail n = reverse . drop n . reverse

snocView :: [a] -> Maybe ([a],a)
        -- Split off the last element
snocView [] = Nothing
snocView xs = go [] xs
            where
                -- Invariant: second arg is non-empty
              go acc [x]    = Just (reverse acc, x)
              go acc (x:xs) = go (x:acc) xs
              go _   []     = panic "Util: snocView"

split :: Char -> String -> [String]
split c s = case rest of
                []     -> [chunk]
                _:rest -> chunk : split c rest
  where (chunk, rest) = break (==c) s
\end{code}


%************************************************************************
%*                                                                      *
\subsection[Utils-comparison]{Comparisons}
%*                                                                      *
%************************************************************************

\begin{code}
isEqual :: Ordering -> Bool
-- Often used in (isEqual (a `compare` b))
isEqual GT = False
isEqual EQ = True
isEqual LT = False

thenCmp :: Ordering -> Ordering -> Ordering
{-# INLINE thenCmp #-}
thenCmp EQ       ordering = ordering
thenCmp ordering _        = ordering

eqListBy :: (a->a->Bool) -> [a] -> [a] -> Bool
eqListBy _  []     []     = True
eqListBy eq (x:xs) (y:ys) = eq x y && eqListBy eq xs ys
eqListBy _  _      _      = False

cmpList :: (a -> a -> Ordering) -> [a] -> [a] -> Ordering
    -- `cmpList' uses a user-specified comparer

cmpList _   []     [] = EQ
cmpList _   []     _  = LT
cmpList _   _      [] = GT
cmpList cmp (a:as) (b:bs)
  = case cmp a b of { EQ -> cmpList cmp as bs; xxx -> xxx }
\end{code}

\begin{code}
removeSpaces :: String -> String
removeSpaces = reverse . dropWhile isSpace . reverse . dropWhile isSpace
\end{code}

%************************************************************************
%*                                                                      *
\subsection[Utils-pairs]{Pairs}
%*                                                                      *
%************************************************************************

\begin{code}
unzipWith :: (a -> b -> c) -> [(a, b)] -> [c]
unzipWith f pairs = map ( \ (a, b) -> f a b ) pairs
\end{code}

\begin{code}
seqList :: [a] -> b -> b
seqList [] b = b
seqList (x:xs) b = x `seq` seqList xs b
\end{code}

Global variables:

\begin{code}
global :: a -> IORef a
global a = unsafePerformIO (newIORef a)
\end{code}

\begin{code}
consIORef :: IORef [a] -> a -> IO ()
consIORef var x = do
  atomicModifyIORef var (\xs -> (x:xs,()))
\end{code}

\begin{code}
globalMVar :: a -> MVar a
globalMVar a = unsafePerformIO (newMVar a)

globalEmptyMVar :: MVar a
globalEmptyMVar = unsafePerformIO newEmptyMVar
\end{code}

Module names:

\begin{code}
looksLikeModuleName :: String -> Bool
looksLikeModuleName [] = False
looksLikeModuleName (c:cs) = isUpper c && go cs
  where go [] = True
        go ('.':cs) = looksLikeModuleName cs
        go (c:cs)   = (isAlphaNum c || c == '_') && go cs
\end{code}

Akin to @Prelude.words@, but acts like the Bourne shell, treating
quoted strings as Haskell Strings, and also parses Haskell [String]
syntax.

\begin{code}
getCmd :: String -> Either String             -- Error
                           (String, String) -- (Cmd, Rest)
getCmd s = case break isSpace $ dropWhile isSpace s of
           ([], _) -> Left ("Couldn't find command in " ++ show s)
           res -> Right res

toCmdArgs :: String -> Either String             -- Error
                              (String, [String]) -- (Cmd, Args)
toCmdArgs s = case getCmd s of
              Left err -> Left err
              Right (cmd, s') -> case toArgs s' of
                                 Left err -> Left err
                                 Right args -> Right (cmd, args)

toArgs :: String -> Either String   -- Error
                           [String] -- Args
toArgs str
    = case dropWhile isSpace str of
      s@('[':_) -> case reads s of
                   [(args, spaces)]
                    | all isSpace spaces ->
                       Right args
                   _ ->
                       Left ("Couldn't read " ++ show str ++ "as [String]")
      s -> toArgs' s
 where
  toArgs' s = case dropWhile isSpace s of
              [] -> Right []
              ('"' : _) -> case reads s of
                           [(arg, rest)]
                              -- rest must either be [] or start with a space
                            | all isSpace (take 1 rest) ->
                               case toArgs' rest of
                               Left err -> Left err
                               Right args -> Right (arg : args)
                           _ ->
                               Left ("Couldn't read " ++ show s ++ "as String")
              s' -> case break isSpace s' of
                    (arg, s'') -> case toArgs' s'' of
                                  Left err -> Left err
                                  Right args -> Right (arg : args)
\end{code}

-- -----------------------------------------------------------------------------
-- Floats

\begin{code}
readRational__ :: ReadS Rational -- NB: doesn't handle leading "-"
readRational__ r = do
     (n,d,s) <- readFix r
     (k,t)   <- readExp s
     return ((n%1)*10^^(k-d), t)
 where
     readFix r = do
        (ds,s)  <- lexDecDigits r
        (ds',t) <- lexDotDigits s
        return (read (ds++ds'), length ds', t)

     readExp (e:s) | e `elem` "eE" = readExp' s
     readExp s                     = return (0,s)

     readExp' ('+':s) = readDec s
     readExp' ('-':s) = do (k,t) <- readDec s
                           return (-k,t)
     readExp' s       = readDec s

     readDec s = do
        (ds,r) <- nonnull isDigit s
        return (foldl1 (\n d -> n * 10 + d) [ ord d - ord '0' | d <- ds ],
                r)

     lexDecDigits = nonnull isDigit

     lexDotDigits ('.':s) = return (span isDigit s)
     lexDotDigits s       = return ("",s)

     nonnull p s = do (cs@(_:_),t) <- return (span p s)
                      return (cs,t)

readRational :: String -> Rational -- NB: *does* handle a leading "-"
readRational top_s
  = case top_s of
      '-' : xs -> - (read_me xs)
      xs       -> read_me xs
  where
    read_me s
      = case (do { (x,"") <- readRational__ s ; return x }) of
          [x] -> x
          []  -> error ("readRational: no parse:"        ++ top_s)
          _   -> error ("readRational: ambiguous parse:" ++ top_s)


-----------------------------------------------------------------------------
-- Create a hierarchy of directories

createDirectoryHierarchy :: FilePath -> IO ()
createDirectoryHierarchy dir | isDrive dir = return () -- XXX Hack
createDirectoryHierarchy dir = do
  b <- doesDirectoryExist dir
  unless b $ do createDirectoryHierarchy (takeDirectory dir)
                createDirectory dir

-----------------------------------------------------------------------------
-- Verify that the 'dirname' portion of a FilePath exists.
--
doesDirNameExist :: FilePath -> IO Bool
doesDirNameExist fpath = case takeDirectory fpath of
                         "" -> return True -- XXX Hack
                         _  -> doesDirectoryExist (takeDirectory fpath)

-- --------------------------------------------------------------
-- check existence & modification time at the same time

modificationTimeIfExists :: FilePath -> IO (Maybe ClockTime)
modificationTimeIfExists f = do
  (do t <- getModificationTime f; return (Just t))
        `IO.catch` \e -> if isDoesNotExistError e
                         then return Nothing
                         else ioError e

-- split a string at the last character where 'pred' is True,
-- returning a pair of strings. The first component holds the string
-- up (but not including) the last character for which 'pred' returned
-- True, the second whatever comes after (but also not including the
-- last character).
--
-- If 'pred' returns False for all characters in the string, the original
-- string is returned in the first component (and the second one is just
-- empty).
splitLongestPrefix :: String -> (Char -> Bool) -> (String,String)
splitLongestPrefix str pred
  | null r_pre = (str,           [])
  | otherwise  = (reverse (tail r_pre), reverse r_suf)
                           -- 'tail' drops the char satisfying 'pred'
  where (r_suf, r_pre) = break pred (reverse str)

escapeSpaces :: String -> String
escapeSpaces = foldr (\c s -> if isSpace c then '\\':c:s else c:s) ""

type Suffix = String

--------------------------------------------------------------
-- * Search path
--------------------------------------------------------------

-- | The function splits the given string to substrings
-- using the 'searchPathSeparator'.
parseSearchPath :: String -> [FilePath]
parseSearchPath path = split path
  where
    split :: String -> [String]
    split s =
      case rest' of
        []     -> [chunk]
        _:rest -> chunk : split rest
      where
        chunk =
          case chunk' of
#ifdef mingw32_HOST_OS
            ('\"':xs@(_:_)) | last xs == '\"' -> init xs
#endif
            _                                 -> chunk'

        (chunk', rest') = break isSearchPathSeparator s

data Direction = Forwards | Backwards

reslash :: Direction -> FilePath -> FilePath
reslash d = f
    where f ('/'  : xs) = slash : f xs
          f ('\\' : xs) = slash : f xs
          f (x    : xs) = x     : f xs
          f ""          = ""
          slash = case d of
                  Forwards -> '/'
                  Backwards -> '\\'
\end{code}

%************************************************************************
%*                                                                      *
\subsection[Utils-Data]{Utils for defining Data instances}
%*                                                                      *
%************************************************************************

These functions helps us to define Data instances for abstract types.

\begin{code}
abstractConstr :: String -> Constr
abstractConstr n = mkConstr (abstractDataType n) ("{abstract:"++n++"}") [] Prefix
\end{code}

\begin{code}
abstractDataType :: String -> DataType
abstractDataType n = mkDataType n [abstractConstr n]
\end{code}

\begin{code}
-- Old GHC versions come with a base library with this function misspelled.
#if __GLASGOW_HASKELL__ < 612
mkNoRepType :: String -> DataType
mkNoRepType = mkNorepType
#endif
\end{code}

