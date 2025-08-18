import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import { now } = "mo:base/Time";
import { abs } = "mo:base/Int";
import Blob "mo:base/Blob";
import Map "mo:map/Map";
import WriteableBand "WriteableBand";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

module DiodeFileSystem {
  // Root directory has a fixed ID of 32 zero bytes
  public let ROOT_DIRECTORY_ID : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";

  // Validation constants
  private let MIN_DIRECTORY_ID_SIZE : Nat = 8;
  private let MIN_CONTENT_HASH_SIZE : Nat = 16;

  public type File = {
    id : Nat;
    timestamp : Nat;
    directory_id : Blob;
    metadata_ciphertext : Blob; // encrypted metadata (name, version_time, etc)
    content_hash : Blob;
    offset : Nat64; // offset to ciphertext in writeable band
    size : Nat64;
    finalized : Bool;
  };

  private type FileInfo = {
    id : Nat;
    timestamp : Nat;
    directory_id : Blob;
    metadata_ciphertext : Blob; // encrypted metadata (name, version_time, etc)
    content_hash : Blob;
  };

  private type BlobInfo = {
    file_ids : [Nat];
    content_hash : Blob;
    offset : Nat64; // offset to ciphertext in writeable band
    size : Nat64;
    finalized : Bool;
  };

  public type Directory = {
    id : Blob;
    metadata_ciphertext : Blob; // encrypted metadata (name, version_time, etc)
    parent_id : ?Blob; // null for root
    timestamp : Nat;
    child_directories : [Blob];
    child_files : [Nat]; // array of global file IDs
  };

  let file_entry_size : Nat64 = 8; // only storing length (Nat64) for the ciphertext

  // Helper function to add a child directory to a parent directory
  private func add_child_directory_to_parent(fs : FileSystem, parent_id : Blob, child_id : Blob) : Result.Result<(), Text> {
    let parent_dir = switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, parent_id)) {
      case (null) { return #err("parent directory not found") };
      case (?dir) { dir };
    };

    let updated_parent : Directory = {
      id = parent_dir.id;
      metadata_ciphertext = parent_dir.metadata_ciphertext;
      parent_id = parent_dir.parent_id;
      timestamp = parent_dir.timestamp;
      child_directories = Array.append(parent_dir.child_directories, [child_id]);
      child_files = parent_dir.child_files;
    };
    Map.set<Blob, Directory>(fs.directories, Map.bhash, parent_id, updated_parent);
    #ok();
  };

  // Helper function to add a file to a directory
  private func add_file_to_directory(fs : FileSystem, directory_id : Blob, file_id : Nat) : Result.Result<(), Text> {
    let dir = switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found") };
      case (?d) { d };
    };

    let updated_directory : Directory = {
      id = dir.id;
      metadata_ciphertext = dir.metadata_ciphertext;
      parent_id = dir.parent_id;
      timestamp = dir.timestamp;
      child_directories = dir.child_directories;
      child_files = Array.append(dir.child_files, [file_id]);
    };
    Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
    #ok();
  };

  public type FileSystem = {
    var files : WriteableBand.WriteableBand; // ring buffer for file contents
    var file_index : Nat;
    var global_files : Map.Map<Nat, FileInfo>; // global file_id -> File map
    var directories : Map.Map<Blob, Directory>;
    var blob_index_map : Map.Map<Blob, BlobInfo>; // content_hash -> BlobInfo
    var max_storage : Nat64;
    var current_storage : Nat64;
    var end_offset : Nat64;
    var next_entry_offset : ?Nat64; // always points to the oldest entry
  };

  public func new(max_storage : Nat64) : FileSystem {
    let fs = {
      var files = WriteableBand.new();
      var file_index = 1 : Nat;
      var global_files = Map.new<Nat, FileInfo>();
      var directories = Map.new<Blob, Directory>();
      var blob_index_map = Map.new<Blob, BlobInfo>();
      var max_storage = max_storage;
      var current_storage = 0 : Nat64;
      var end_offset = 0 : Nat64;
      var next_entry_offset = null : ?Nat64; // no entries to remove in empty filesystem
    };

    // Create the root directory automatically
    let root_directory : Directory = {
      id = ROOT_DIRECTORY_ID;
      metadata_ciphertext = ""; // Root has empty metadata
      parent_id = null; // Root has no parent
      timestamp = abs(now()) / 1_000_000_000;
      child_directories = [];
      child_files = [];
    };
    Map.set<Blob, Directory>(fs.directories, Map.bhash, ROOT_DIRECTORY_ID, root_directory);

    return fs;
  };

  public func set_max_storage(fs : FileSystem, max_storage : Nat64) {
    fs.max_storage := max_storage;
  };

  public func create_directory(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, parent_id : ?Blob) : Result.Result<(), Text> {
    if (directory_id.size() < MIN_DIRECTORY_ID_SIZE) {
      return #err("directory_id must be at least " # Nat.toText(MIN_DIRECTORY_ID_SIZE) # " bytes");
    };

    // Prevent creating directory with the reserved root ID
    if (directory_id == ROOT_DIRECTORY_ID) {
      return #err("cannot create directory with reserved root ID");
    };

    // Prevent creating orphaned directories - all directories except root must have a valid parent
    switch (parent_id) {
      case (null) {
        return #err("cannot create directory without parent - only root directory can have null parent");
      };
      case (?parent) {
        // Verify parent directory exists
        switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, parent)) {
          case (null) {
            return #err("parent directory not found");
          };
          case (?_parent_dir) {
            // Parent exists, continue
          };
        };
      };
    };

    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) {
        // passthrough
      };
      case (?_value) {
        return #err("directory already exists");
      };
    };

    let directory : Directory = {
      id = directory_id;
      metadata_ciphertext = name_ciphertext;
      parent_id = parent_id;
      timestamp = abs(now()) / 1_000_000_000;
      child_directories = [];
      child_files = [];
    };

    Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, directory);

    // Add to parent's child_directories (parent is guaranteed to exist due to earlier validation)
    switch (parent_id) {
      case (null) {
        // This case should never happen due to earlier validation
        return #err("internal error: null parent_id after validation");
      };
      case (?parent) {
        switch (add_child_directory_to_parent(fs, parent, directory_id)) {
          case (#ok()) {};
          case (#err(err)) { return #err("internal error: " # err) };
        };
      };
    };

    return #ok();
  };

  public func write_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, ciphertext : Blob) : Result.Result<Nat, Text> {
    switch (allocate_file(fs, directory_id, name_ciphertext, content_hash, Nat64.fromNat(ciphertext.size()))) {
      case (#err(err)) {
        return #err(err);
      };
      case (#ok(file)) {
        if (file.finalized) {
          // File already exists and is finalized (deduplication case)
          return #ok(file.id);
        } else {
          // File is new and needs to be written and finalized
          switch (write_file_chunk(fs, content_hash, 0, ciphertext)) {
            case (#err(err)) {
              let _ = delete_file(fs, file.id);
              return #err(err);
            };
            case (#ok()) {
              switch (finalize_file(fs, content_hash)) {
                case (#err(err)) {
                  let _ = delete_file(fs, file.id);
                  return #err(err);
                };
                case (#ok()) {
                  return #ok(file.id);
                };
              };
            };
          };
        };
      };
    };
  };

  public func delete_file(fs : FileSystem, file_id : Nat) : Result.Result<(), Text> {
    switch (Map.get<Nat, FileInfo>(fs.global_files, Map.nhash, file_id)) {
      case (null) {
        return #err("file not found");
      };
      case (?file_info) {
        // Get blob info
        let blob_info = switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, file_info.content_hash)) {
          case (null) { return #err("blob not found") };
          case (?b) { b };
        };

        // Remove from file index maps
        Map.delete<Nat, FileInfo>(fs.global_files, Map.nhash, file_id);
        let new_file_ids = Array.filter<Nat>(blob_info.file_ids, func(fid : Nat) : Bool { fid != file_id });
        let new_blob_info : BlobInfo = {
          file_ids = new_file_ids;
          content_hash = blob_info.content_hash;
          offset = blob_info.offset;
          size = blob_info.size;
          finalized = blob_info.finalized;
        };
        Map.set<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, file_info.content_hash, new_blob_info);
        return #ok();
      };
    };
  };

  public func allocate_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, size : Nat64) : Result.Result<File, Text> {
    if (directory_id.size() < MIN_DIRECTORY_ID_SIZE) {
      return #err("directory_id must be at least " # Nat.toText(MIN_DIRECTORY_ID_SIZE) # " bytes");
    };
    if (content_hash.size() < MIN_CONTENT_HASH_SIZE) {
      return #err("content_hash must be at least " # Nat.toText(MIN_CONTENT_HASH_SIZE) # " bytes");
    };
    if (size == 0) {
      return #err("size must be greater than 0");
    };

    // Check if directory exists
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found") };
      case (?_directory) { };
    };

    // Check if file already exists (content deduplication)
    switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash)) {
      case (null) {
        /* passthrough - file doesn't exist, continue with allocation */
      };
      case (?blob_info) {
        // Blob exists, add file to directory
        let file_info : FileInfo = {
          id = fs.file_index;
          timestamp = abs(now()) / 1_000_000_000;
          directory_id = directory_id;
          metadata_ciphertext = name_ciphertext;
          content_hash = content_hash;
        };

        Map.set<Nat, FileInfo>(fs.global_files, Map.nhash, fs.file_index, file_info);
        let updated_blob : BlobInfo = {
          file_ids = Array.append(blob_info.file_ids, [file_info.id]);
          content_hash = blob_info.content_hash;
          offset = blob_info.offset;
          size = blob_info.size;
          finalized = blob_info.finalized;
        };
        Map.set<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash, updated_blob);

        switch (add_file_to_directory(fs, directory_id, file_info.id)) {
          case (#ok()) {};
          case (#err(err)) { return #err(err) };
        };

        fs.file_index += 1;
        return #ok({
          id = file_info.id;
          timestamp = file_info.timestamp;
          directory_id = file_info.directory_id;
          metadata_ciphertext = file_info.metadata_ciphertext;
          content_hash = file_info.content_hash;
          offset = blob_info.offset;
          size = blob_info.size;
          finalized = blob_info.finalized;
        });
      };
    };

    let total_size = size + file_entry_size;
    ensure_ring_buffer_space(fs, total_size);

    // Wrap if needed
    if (fs.end_offset + total_size > fs.max_storage) {
      fs.end_offset := 0;
    };

    // Allocate space for file length + content
    let content_offset = fs.end_offset;
    WriteableBand.writeNat64(fs.files, content_offset, size); // store length first
    // Content space is reserved but not written yet (will be written by write_file_chunk)

    fs.end_offset += total_size;
    fs.current_storage += total_size;

    // Update next_entry_offset to point to oldest entry if this is the first file
    if (fs.next_entry_offset == null) {
      fs.next_entry_offset := ?content_offset;
    };

    let blob_info : BlobInfo = {
      file_ids = [fs.file_index];
      content_hash = content_hash;
      offset = content_offset + 8; // offset to actual ciphertext (after length)
      size = size;
      finalized = false;
    };
    Map.set<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash, blob_info);

    // Create File struct (unfinalized)
    let file : FileInfo = {
      id = fs.file_index;
      timestamp = abs(now()) / 1_000_000_000;
      directory_id = directory_id;
      metadata_ciphertext = name_ciphertext;
      content_hash = content_hash;
    };

    // Store in global files map
    Map.set<Nat, FileInfo>(fs.global_files, Map.nhash, fs.file_index, file);

    // Add to directory's child_files
    switch (add_file_to_directory(fs, directory_id, fs.file_index)) {
      case (#ok()) {};
      case (#err(err)) { return #err(err) };
    };

    fs.file_index += 1;
    return #ok({
      id = file.id;
      timestamp = file.timestamp;
      directory_id = file.directory_id;
      metadata_ciphertext = file.metadata_ciphertext;
      content_hash = file.content_hash;
      offset = blob_info.offset;
      size = blob_info.size;
      finalized = false;
    });
  };

  public func write_file_chunk(fs : FileSystem, content_hash : Blob, chunk_offset : Nat64, chunk : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?blob_info) {
        // Get file from global files map
        if (blob_info.finalized) {
          return #err("file is already finalized");
        };

        if (chunk_offset + Nat64.fromNat(chunk.size()) > blob_info.size) {
          return #err("chunk out of bounds");
        };

        // Calculate content offset
        let content_offset = blob_info.offset + chunk_offset;
        WriteableBand.writeBlob(fs.files, content_offset, chunk);
        return #ok();
      };
    };
  };

  public func finalize_file(fs : FileSystem, content_hash : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?blob_info) {
        // Check if already finalized
        if (blob_info.finalized) {
          return #ok(); // Already finalized, nothing to do
        };

        // Update the File struct in global files map to mark as finalized
        let finalized_blob : BlobInfo = {
          file_ids = blob_info.file_ids;
          content_hash = blob_info.content_hash;
          offset = blob_info.offset;
          size = blob_info.size;
          finalized = true;
        };

        Map.set<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash, finalized_blob);
        return #ok();
      };
    };
  };

  public func read_file_chunk(fs : FileSystem, content_hash : Blob, chunk_offset : Nat64, chunk_size : Nat) : Result.Result<Blob, Text> {
    switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?blob_info) {
        if (not blob_info.finalized) {
          return #err("file is not finalized");
        };

        if (chunk_offset + Nat64.fromNat(chunk_size) > blob_info.size) {
          return #err("chunk out of bounds");
        };

        // Calculate content offset
        let content_offset = blob_info.offset + chunk_offset;
        let chunk = WriteableBand.readBlob(fs.files, content_offset, chunk_size);
        return #ok(chunk);
      };
    };
  };

  private func ensure_ring_buffer_space(fs : FileSystem, total_size : Nat64) {
    // Remove files if we exceed storage capacity
    while (fs.current_storage + total_size > fs.max_storage) {
      if (fs.next_entry_offset == null) return; // No more files to remove
      let prev_storage = fs.current_storage;
      remove_next_file_entry(fs);
      if (fs.current_storage == prev_storage) return; // Avoid infinite loop
    };
  };

  private func remove_next_file_entry(fs : FileSystem) {
    switch (fs.next_entry_offset) {
      case (null) { return };
      case (?length_offset) {
        // Read the file size from WriteableBand
        let size = WriteableBand.readNat64(fs.files, length_offset);

        // Find the file that has this offset (length_offset + 8)
        let ciphertext_offset = length_offset + 8;
        var found_blob : ?BlobInfo = null;

        label find_loop for ((content_hash, blob_info) in Map.entries(fs.blob_index_map)) {
          if (blob_info.offset == ciphertext_offset) {
            found_blob := ?blob_info;
            break find_loop;
          };
        };

        switch (found_blob) {
          case (?blob_info) {
            for (file_id in blob_info.file_ids.vals()) {
              let _ = delete_file(fs, file_id);
            };

            // Remove from file index and global files map
            Map.delete<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, blob_info.content_hash);

            // Update current storage
            let total_file_size = size + file_entry_size;
            if (fs.current_storage >= total_file_size) {
              fs.current_storage -= total_file_size;
            } else {
              fs.current_storage := 0;
            };

            // Mark entry as empty by setting size to 0
            WriteableBand.writeNat64(fs.files, length_offset, 0);

            // Advance next_entry_offset to next entry in ring buffer
            let next_offset = length_offset + total_file_size;
            if (next_offset >= fs.max_storage) {
              // Wrap around to beginning
              fs.next_entry_offset := ?0;
            } else {
              fs.next_entry_offset := ?next_offset;
            };

            // Check if the next entry is empty or if we've wrapped around to our end position
            // If so, there are no more files to remove
            switch (fs.next_entry_offset) {
              case (?next_pos) {
                if (next_pos >= fs.end_offset) {
                  // We've caught up to the current end, no more files to remove
                  fs.next_entry_offset := null;
                } else {
                  // Check if the next entry has size 0 (empty)
                  let next_size = WriteableBand.readNat64(fs.files, next_pos);
                  if (next_size == 0) {
                    // Next entry is empty, no more files to remove
                    fs.next_entry_offset := null;
                  };
                };
              };
              case (null) { /* already null */ };
            };
          };
          case (null) {
            // File not found, just set next_entry_offset to null
            fs.next_entry_offset := null;
          };
        };
      };
    };
  };

  public func get_file_by_hash(fs : FileSystem, content_hash : Blob) : Result.Result<File, Text> {
    switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, content_hash)) {
      case (null) { #err("file not found") };
      case (?blob_info) {
        if (blob_info.file_ids.size() == 0) {
          #err("file not found");
        } else {
          switch (get_file_by_id(fs, blob_info.file_ids[0])) {
            case (null) { #err("file not found in directories") };
            case (?file) { #ok(file) };
          };
        };
      };
    };
  };

  public func get_file_by_id(fs : FileSystem, file_id : Nat) : ?File {
    switch (Map.get<Nat, FileInfo>(fs.global_files, Map.nhash, file_id)) {
      case (null) { null };
      case (?file_info) {
        switch (Map.get<Blob, BlobInfo>(fs.blob_index_map, Map.bhash, file_info.content_hash)) {
          case (null) { null };
          case (?blob_info) {
            return ?{
              id = file_info.id;
              timestamp = file_info.timestamp;
              directory_id = file_info.directory_id;
              metadata_ciphertext = file_info.metadata_ciphertext;
              content_hash = file_info.content_hash;
              offset = blob_info.offset;
              size = blob_info.size;
              finalized = blob_info.finalized;
            };
          };
        };
      };
    };
  };

  public func get_directory(fs : FileSystem, directory_id : Blob) : ?Directory {
    return Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
  };

  public func get_root_directory(fs : FileSystem) : ?Directory {
    return Map.get<Blob, Directory>(fs.directories, Map.bhash, ROOT_DIRECTORY_ID);
  };

  public func get_files_in_directory(fs : FileSystem, directory_id : Blob) : [File] {
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { [] };
      case (?directory) {
        let files = Array.mapFilter<Nat, File>(
          directory.child_files,
          func(file_id : Nat) : ?File {
            switch (get_file_by_id(fs, file_id)) {
              case (null) { null };
              case (?file) {
                if (file.finalized) {
                  ?file;
                } else {
                  null;
                };
              };
            };
          },
        );
        files;
      };
    };
  };

  public func get_child_directories(fs : FileSystem, directory_id : Blob) : [Directory] {
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { [] };
      case (?directory) {
        let child_ids = directory.child_directories;
        // Use mapFilter to handle missing directories correctly
        let children = Array.mapFilter<Blob, Directory>(
          child_ids,
          func(child_id : Blob) : ?Directory {
            get_directory(fs, child_id);
          },
        );
        children;
      };
    };
  };

  public func get_last_file_id(fs : FileSystem) : Nat {
    if (fs.file_index > 0) {
      return fs.file_index - 1;
    } else {
      return 0;
    };
  };

  public func get_usage(fs : FileSystem) : Nat64 {
    return fs.current_storage;
  };

  public func get_max_usage(fs : FileSystem) : Nat64 {
    return fs.max_storage;
  };

  public func get_file_count(fs : FileSystem) : Nat {
    return Map.size(fs.global_files);
  };

  public func get_directory_count(fs : FileSystem) : Nat {
    return Map.size(fs.directories);
  };
};
