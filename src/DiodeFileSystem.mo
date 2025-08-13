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

  public type Directory = {
    id : Blob;
    metadata_ciphertext : Blob; // encrypted metadata (name, version_time, etc)
    parent_id : ?Blob; // null for root
    timestamp : Nat;
    child_directories : [Blob];
    child_files : [Nat]; // array of global file IDs
  };

  let file_entry_size : Nat64 = 8; // only storing length (Nat64) for the ciphertext

  public type FileSystem = {
    var files : WriteableBand.WriteableBand; // ring buffer for file contents
    var file_index : Nat;
    var global_files : Map.Map<Nat, File>; // global file_id -> File map
    var directories : Map.Map<Blob, Directory>;
    var file_index_map : Map.Map<Blob, Nat>; // content_hash -> file_id
    var max_storage : Nat64;
    var current_storage : Nat64;
    var first_entry_offset : Nat64;
    var end_offset : Nat64;
    var next_entry_offset : ?Nat64; // always points to the oldest entry
  };

  public func new(max_storage : Nat64) : FileSystem {
    let fs = {
      var files = WriteableBand.new();
      var file_index = 1 : Nat;
      var global_files = Map.new<Nat, File>();
      var directories = Map.new<Blob, Directory>();
      var file_index_map = Map.new<Blob, Nat>();
      var max_storage = max_storage;
      var current_storage = 0 : Nat64;
      var first_entry_offset = 0 : Nat64;
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
    if (directory_id.size() < 8) {
      return #err("directory_id must be at least 8 bytes");
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
        let parent_dir = switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, parent)) {
          case (null) {
            // This should never happen due to earlier validation
            return #err("internal error: parent directory disappeared");
          };
          case (?dir) { dir };
        };

        let updated_parent : Directory = {
          id = parent_dir.id;
          metadata_ciphertext = parent_dir.metadata_ciphertext;
          parent_id = parent_dir.parent_id;
          timestamp = parent_dir.timestamp;
          child_directories = Array.append(parent_dir.child_directories, [directory_id]);
          child_files = parent_dir.child_files;
        };
        Map.set<Blob, Directory>(fs.directories, Map.bhash, parent, updated_parent);
      };
    };

    return #ok();
  };

  public func add_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, ciphertext : Blob) : Result.Result<Nat, Text> {
    if (directory_id.size() < 8) {
      return #err("directory_id must be at least 8 bytes");
    };
    if (content_hash.size() < 16) {
      return #err("content_hash must be at least 16 bytes");
    };
    // Check if file already exists
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) { /* passthrough */ };
      case (?value) { return #ok(value) };
    };
    // Check if directory exists
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found") };
      case (?_directory) { /* passthrough */ };
    };
    let file_size = Nat64.fromNat(ciphertext.size());
    let total_size = file_size + file_entry_size;
    ensureRingBufferSpace(fs, total_size);
    // Entry will not fit in the current space, wrap around to the beginning
    if (fs.end_offset + total_size > fs.max_storage) {
      fs.end_offset := 0;

      // When wrapping, remove files that would be overwritten
      let new_file_end = fs.end_offset + total_size;
      label removal_loop while (fs.next_entry_offset != null) {
        let entry_offset = switch (fs.next_entry_offset) {
          case (?offset) { offset };
          case null { break removal_loop };
        };

        // If this entry or its content would be overwritten by the new file, remove it
        // The content starts before the entry, and the entry ends at entry_offset + file_entry_size
        if (entry_offset < new_file_end) {
          // This entry will be overwritten, remove the file
          remove_next_file_entry(fs);
        } else {
          break removal_loop; // No more overlapping files
        };
      };
    };

    // Write file length and content
    let content_offset = fs.end_offset;
    WriteableBand.writeNat64(fs.files, content_offset, file_size); // store length first
    WriteableBand.writeBlob(fs.files, content_offset + 8, ciphertext); // then ciphertext
    fs.end_offset += total_size;
    fs.current_storage += total_size;

    // Set next_entry_offset to point to the first entry when adding the first file
    if (fs.next_entry_offset == null) {
      fs.next_entry_offset := ?content_offset;
    };

    // Update file index
    Map.set<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash, fs.file_index);

    // Create File struct
    let file : File = {
      id = fs.file_index;
      timestamp = abs(now()) / 1_000_000_000;
      directory_id = directory_id;
      metadata_ciphertext = name_ciphertext;
      content_hash = content_hash;
      offset = content_offset + 8; // offset to actual ciphertext (after length)
      size = file_size;
      finalized = true;
    };

    // Store in global files map
    Map.set<Nat, File>(fs.global_files, Map.nhash, fs.file_index, file);

    // Update directory's child_files
    let directory = Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
    switch (directory) {
      case (null) { return #err("directory not found during update") };
      case (?dir) {
        let updated_directory : Directory = {
          id = dir.id;
          metadata_ciphertext = dir.metadata_ciphertext;
          parent_id = dir.parent_id;
          timestamp = dir.timestamp;
          child_directories = dir.child_directories;
          child_files = Array.append(dir.child_files, [fs.file_index]);
        };
        Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
      };
    };
    let result_id = fs.file_index;
    fs.file_index += 1;
    return #ok(result_id);
  };

  public func write_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, ciphertext : Blob) : Result.Result<Nat, Text> {
    switch (allocate_file(fs, directory_id, name_ciphertext, content_hash, Nat64.fromNat(ciphertext.size()))) {
      case (#err(err)) {
        return #err(err);
      };
      case (#ok(file_id)) {
        switch (write_file_chunk(fs, content_hash, 0, ciphertext)) {
          case (#err(err)) {
            let _ = delete_file(fs, content_hash);
            return #err(err);
          };
          case (#ok()) {
            switch (finalize_file(fs, content_hash)) {
              case (#err(err)) {
                let _ = delete_file(fs, content_hash);
                return #err(err);
              };
              case (#ok()) {
                return #ok(file_id);
              };
            };
          };
        };
      };
    };
  };

  public func delete_file(fs : FileSystem, content_hash : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?file_id) {
        // Get file from global files map
        let file = switch (Map.get<Nat, File>(fs.global_files, Map.nhash, file_id)) {
          case (null) { return #err("file not found in global files") };
          case (?f) { f };
        };

        let directory_id = file.directory_id;

        // Remove from file index maps
        Map.delete<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash);
        Map.delete<Nat, File>(fs.global_files, Map.nhash, file_id);

        // Remove from directory's child_files array
        switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
          case (null) {
            return #err("directory not found during delete");
          };
          case (?dir) {
            let updated_directory : Directory = {
              id = dir.id;
              metadata_ciphertext = dir.metadata_ciphertext;
              parent_id = dir.parent_id;
              timestamp = dir.timestamp;
              child_directories = dir.child_directories;
              child_files = Array.filter<Nat>(dir.child_files, func(fid : Nat) : Bool { fid != file_id });
            };
            Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
          };
        };

        // Mark entry as deleted by setting length to 0
        let length_offset = file.offset - 8; // length is stored 8 bytes before ciphertext
        WriteableBand.writeNat64(fs.files, length_offset, 0);

        // Update storage counters
        let total_size = file.size + file_entry_size;
        if (fs.current_storage >= total_size) {
          fs.current_storage -= total_size;
        } else {
          fs.current_storage := 0;
        };

        return #ok();
      };
    };
  };

  public func allocate_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, size : Nat64) : Result.Result<Nat, Text> {
    if (directory_id.size() < 8) {
      return #err("directory_id must be at least 8 bytes");
    };
    if (content_hash.size() < 16) {
      return #err("content_hash must be at least 16 bytes");
    };
    if (size == 0) {
      return #err("size must be greater than 0");
    };

    // Check if file already exists
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) { /* passthrough */ };
      case (?value) { return #ok(value) };
    };

    // Check if directory exists
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found") };
      case (?_directory) { /* passthrough */ };
    };

    let total_size = size + file_entry_size;
    ensureRingBufferSpace(fs, total_size);

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

    // Update file index
    Map.set<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash, fs.file_index);

    // Create File struct (unfinalized)
    let file : File = {
      id = fs.file_index;
      timestamp = abs(now()) / 1_000_000_000;
      directory_id = directory_id;
      metadata_ciphertext = name_ciphertext;
      content_hash = content_hash;
      offset = content_offset + 8; // offset to actual ciphertext (after length)
      size = size;
      finalized = false;
    };

    // Store in global files map
    Map.set<Nat, File>(fs.global_files, Map.nhash, fs.file_index, file);

    // Add to directory's child_files
    let directory = Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
    switch (directory) {
      case (null) { return #err("directory not found during allocate") };
      case (?dir) {
        let updated_directory : Directory = {
          id = dir.id;
          metadata_ciphertext = dir.metadata_ciphertext;
          parent_id = dir.parent_id;
          timestamp = dir.timestamp;
          child_directories = dir.child_directories;
          child_files = Array.append(dir.child_files, [fs.file_index]);
        };
        Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
      };
    };

    let result_id = fs.file_index;
    fs.file_index += 1;
    return #ok(result_id);
  };

  public func write_file_chunk(fs : FileSystem, content_hash : Blob, chunk_offset : Nat64, chunk : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?file_id) {
        // Get file from global files map
        let file = switch (Map.get<Nat, File>(fs.global_files, Map.nhash, file_id)) {
          case (null) { return #err("file not found") };
          case (?f) { f };
        };

        if (file.finalized) {
          return #err("file is already finalized");
        };

        if (chunk_offset + Nat64.fromNat(chunk.size()) > file.size) {
          return #err("chunk out of bounds");
        };

        // Calculate content offset
        let content_offset = file.offset + chunk_offset;
        WriteableBand.writeBlob(fs.files, content_offset, chunk);
        return #ok();
      };
    };
  };

  public func finalize_file(fs : FileSystem, content_hash : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?file_id) {
        // Get file from global files map
        let file = switch (Map.get<Nat, File>(fs.global_files, Map.nhash, file_id)) {
          case (null) { return #err("file not found") };
          case (?f) { f };
        };

        // Check if already finalized
        if (file.finalized) {
          return #ok(); // Already finalized, nothing to do
        };

        // Update the File struct in global files map to mark as finalized
        let finalized_file : File = {
          id = file.id;
          timestamp = file.timestamp;
          directory_id = file.directory_id;
          metadata_ciphertext = file.metadata_ciphertext;
          content_hash = file.content_hash;
          offset = file.offset;
          size = file.size;
          finalized = true;
        };

        Map.set<Nat, File>(fs.global_files, Map.nhash, file_id, finalized_file);

        return #ok();
      };
    };
  };

  public func read_file_chunk(fs : FileSystem, content_hash : Blob, chunk_offset : Nat64, chunk_size : Nat) : Result.Result<Blob, Text> {
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?file_id) {
        // Get file from global files map
        let file = switch (Map.get<Nat, File>(fs.global_files, Map.nhash, file_id)) {
          case (null) { return #err("file not found") };
          case (?f) { f };
        };

        if (not file.finalized) {
          return #err("file is not finalized");
        };

        if (chunk_offset + Nat64.fromNat(chunk_size) > file.size) {
          return #err("chunk out of bounds");
        };

        // Calculate content offset
        let content_offset = file.offset + chunk_offset;
        let chunk = WriteableBand.readBlob(fs.files, content_offset, chunk_size);
        return #ok(chunk);
      };
    };
  };

  private func ensureRingBufferSpace(fs : FileSystem, total_size : Nat64) {
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
        var found_file : ?File = null;

        label find_loop for ((file_id, file) in Map.entries(fs.global_files)) {
          if (file.offset == ciphertext_offset) {
            found_file := ?file;
            break find_loop;
          };
        };

        switch (found_file) {
          case (?file) {
            let file_id = file.id;
            let content_hash = file.content_hash;
            let directory_id = file.directory_id;

            // Remove from file index and global files map
            Map.delete<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash);
            Map.delete<Nat, File>(fs.global_files, Map.nhash, file_id);

            // Update directory file entries
            switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
              case (null) {};
              case (?dir) {
                let updated_directory : Directory = {
                  id = dir.id;
                  metadata_ciphertext = dir.metadata_ciphertext;
                  parent_id = dir.parent_id;
                  timestamp = dir.timestamp;
                  child_directories = dir.child_directories;
                  child_files = Array.filter<Nat>(dir.child_files, func(fid : Nat) : Bool { fid != file_id });
                };
                Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
              };
            };
            // Update current storage
            let total_file_size = size + file_entry_size;
            if (fs.current_storage >= total_file_size) {
              fs.current_storage -= total_file_size;
            } else {
              fs.current_storage := 0;
            };

            // Mark entry as empty by setting size to 0
            WriteableBand.writeNat64(fs.files, length_offset, 0);
            // For now, just set to null. It will be recalculated when needed.
            fs.next_entry_offset := null;
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
    switch (Map.get<Blob, Nat>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) { #err("file not found") };
      case (?file_id) {
        switch (get_file_by_id(fs, file_id)) {
          case (null) { #err("file not found in directories") };
          case (?file) { #ok(file) };
        };
      };
    };
  };

  public func get_file_by_id(fs : FileSystem, file_id : Nat) : ?File {
    return Map.get<Nat, File>(fs.global_files, Map.nhash, file_id);
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
            switch (Map.get<Nat, File>(fs.global_files, Map.nhash, file_id)) {
              case (?file) {
                if (file.finalized) { ?file } else { null };
              };
              case (null) { null };
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
        let children = Array.init<Directory>(child_ids.size(), directory); // placeholder
        var index = 0;
        for (child_id in child_ids.vals()) {
          switch (get_directory(fs, child_id)) {
            case (null) {};
            case (?child) {
              children[index] := child;
            };
          };
          index += 1;
        };
        Array.freeze(children);
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
    return Map.size(fs.file_index_map);
  };

  public func get_directory_count(fs : FileSystem) : Nat {
    return Map.size(fs.directories);
  };
};
