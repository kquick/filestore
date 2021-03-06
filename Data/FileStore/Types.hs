{-# LANGUAGE Rank2Types, TypeSynonymInstances, DeriveDataTypeable, FlexibleInstances #-}
{- |
   Module      : Data.FileStore.Types
   Copyright   : Copyright (C) 2009 John MacFarlane
   License     : BSD 3

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : GHC 6.10 required

   Type definitions for "Data.FileStore".
-}

module Data.FileStore.Types
           ( RevisionId
           , Resource(..)
           , Author(..)
           , Change(..)
           , Description
           , Revision(..)
           , Contents(..)
           , TimeRange(..)
           , MergeInfo(..)
           , FileStoreError(..)
           , SearchMatch(..)
           , SearchQuery(..)
           , defaultSearchQuery
           , UTCTime
           , FileStore (..) )

where
import Data.ByteString.Lazy (ByteString)
import Data.Typeable
import Data.ByteString.Lazy.UTF8 (toString, fromString)
import Data.Time (UTCTime)
import Control.Exception (Exception)

type RevisionId   = String

data Resource = FSFile FilePath
              | FSDirectory FilePath
              deriving (Show, Read, Eq, Typeable, Ord)

data Author =
  Author {
    authorName  :: String
  , authorEmail :: String
  } deriving (Show, Read, Eq, Typeable)

data Change =
    Added FilePath
  | Deleted FilePath
  | Modified FilePath
  deriving (Show, Read, Eq, Typeable)

type Description = String

data Revision =
  Revision {
    revId          :: RevisionId
  , revDateTime    :: UTCTime
  , revAuthor      :: Author
  , revDescription :: Description
  , revChanges     :: [Change]
  } deriving (Show, Read, Eq, Typeable)

class Contents a where
  fromByteString :: ByteString -> a
  toByteString   :: a -> ByteString

instance Contents ByteString where
  toByteString = id
  fromByteString = id

instance Contents String where
  toByteString   = fromString
  fromByteString = toString

data TimeRange =
  TimeRange {
    timeFrom :: Maybe UTCTime  -- ^ @Nothing@ means no lower bound
  , timeTo   :: Maybe UTCTime  -- ^ @Nothing@ means no upper bound
  } deriving (Show, Read, Eq, Typeable)

data MergeInfo =
  MergeInfo {
    mergeRevision  :: Revision   -- ^ The revision w/ which changes were merged
  , mergeConflicts :: Bool       -- ^ @True@ if there were merge conflicts
  , mergeText      :: String     -- ^ The merged text, w/ conflict markers
  } deriving (Show, Read, Eq, Typeable)

data FileStoreError =
    RepositoryExists             -- ^ Tried to initialize a repo that exists
  | ResourceExists               -- ^ Tried to create a resource that exists
  | NotFound                     -- ^ Requested resource was not found
  | IllegalResourceName          -- ^ The specified resource name is illegal
  | Unchanged                    -- ^ The resource was not modified,
                                 --   because the contents were unchanged
  | UnsupportedOperation
  | NoMaxCount                   -- ^ The darcs version used does not support
                                 --   --max-count
  | UnknownError String
  deriving (Read, Eq, Typeable)

instance Show FileStoreError where
  show RepositoryExists      = "RepositoryExists"
  show ResourceExists        = "ResourceExists"
  show NotFound              = "NotFound"
  show IllegalResourceName   = "IllegalResourceName"
  show Unchanged             = "Unchanged"
  show UnsupportedOperation  = "UnsupportedOperation"
  show NoMaxCount            = "NoMaxCount:\n"
    ++ "filestore was compiled with the maxcount flag, but your version of\n"
    ++ "darcs does not support the --max-count option.  You should either\n"
    ++ "upgrade to darcs >= 2.3.0 (recommended) or compile filestore without\n"
    ++ "the maxcount flag (cabal install filestore -f-maxcount)."
  show (UnknownError s)      = "UnknownError: " ++ s

instance Exception FileStoreError

data SearchQuery =
  SearchQuery {
    queryPatterns    :: [String] -- ^ Patterns to match
  , queryWholeWords  :: Bool     -- ^ Match patterns only with whole words?
  , queryMatchAll    :: Bool     -- ^ Return matches only from files in which
                                 --   all patterns match?
  , queryIgnoreCase  :: Bool     -- ^ Make matches case-insensitive?
  } deriving (Show, Read, Eq, Typeable)

defaultSearchQuery :: SearchQuery
defaultSearchQuery = SearchQuery {
     queryPatterns   = []
   , queryWholeWords = True
   , queryMatchAll   = True
   , queryIgnoreCase = True
   }

data SearchMatch =
  SearchMatch {
    matchResourceName :: FilePath
  , matchLineNumber   :: Integer
  , matchLine         :: String
  } deriving (Show, Read, Eq, Typeable)

-- | A versioning filestore, which can be implemented using the
-- file system, a database, or revision-control software.
data FileStore = FileStore {

    -- | Initialize a new filestore.
    initialize     :: IO ()

    -- | Save contents in the filestore.
  , save           :: forall a . Contents a
                   => FilePath          -- Resource to save.
                   -> Author            --  Author of change.
                   -> Description       --  Description of change.
                   -> a                 --  New contents of resource.
                   -> IO ()

    -- | Retrieve the contents of the named resource.
  , retrieve       :: forall a . Contents a
                   => FilePath          -- Resource to retrieve.
                   -> Maybe RevisionId  -- @Just@ a particular revision ID,
                                        -- or @Nothing@ for latest
                   -> IO a

    -- | Delete a named resource, providing author and log message.
  , delete         :: FilePath          -- Resource to delete.
                   -> Author            -- Author of change.
                   -> Description       -- Description of change.
                   -> IO ()

    -- | Rename a resource, providing author and log message.
  , rename         :: FilePath          -- Resource original name.
                   -> FilePath          -- Resource new name.
                   -> Author            -- Author of change.
                   -> Description       -- Description of change.
                   -> IO ()

    -- | Get history for a list of named resources in a (possibly openended)
    -- time range. If the list is empty, history for all resources will
    -- be returned. If the TimeRange is 2 Nothings, history for all dates will be returned.
  , history        :: [FilePath]        -- List of resources to get history for
                                        -- or @[]@ for all.
                   -> TimeRange         -- Time range in which to get history.
                   -> Maybe Int         -- Maybe max number of entries.
                   -> IO [Revision]

    -- | Return the revision ID of the latest change for a resource.
    -- Raises 'NotFound' if the resource is not found.
  , latest         :: FilePath          -- Resource to get revision ID for.
                   -> IO RevisionId

    -- | Return information about a revision, given the ID.
    -- Raises 'NotFound' if there is no such revision.
  , revision       :: RevisionId        -- Revision ID to get information for.
                   -> IO Revision

    -- | Return a list of resources in the filestore.
  , index          :: IO [FilePath]

  -- | Return a list of resources in a directory of the filestore.
  , directory      :: FilePath          -- Directory to list (empty for root)
                   -> IO [Resource]

    -- | @True@ if the revision IDs match, in the sense that the
    -- can be treated as specifying the same revision.
  , idsMatch       :: RevisionId
                   -> RevisionId
                   -> Bool

  -- | Search the filestore for patterns.
  , search         :: SearchQuery
                   -> IO [SearchMatch]

  }
