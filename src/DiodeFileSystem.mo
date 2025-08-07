import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import { now } = "mo:base/Time";
import { abs } = "mo:base/Int";
import Blob "mo:base/Blob";
import Map "mo:map/Map";
import WriteableBand "WriteableBand";
import Array "mo:base/Array";

module DiodeFileSystem {
  public type File = {
    id : Nat32;
    timestamp : Nat32;
    name_ciphertext : Blob; // encrypted filename
    content_hash : Blob;
    offset : Nat64; // offset to ciphertext content in WriteableBand
    size : Nat64;
    finalized : Bool;
  };

  public type Directory = {
    id : Blob;
    name_ciphertext : Blob; // encrypted directory name
    parent_id : ?Blob; // null for root
    timestamp : Nat32;
    child_directories : [Blob];
    child_files : [File];
  };

  let file_entry_size : Nat64 = 120; // 4 + 4 + 32 + 32 + 32 + 8 + 4 + 4; // id + timestamp + directory_id + name_ciphertext + content_hash + size + finalized + reserved

  public type FileSystem = {
    var files : WriteableBand.WriteableBand; // ring buffer for file contents
    var file_index : Nat32;
    var directories : Map.Map<Blob, Directory>;
    var max_storage : Nat64;
    var current_storage : Nat64;
    var first_entry_offset : Nat64;
    var end_offset : Nat64;
    var next_entry_offset : ?Nat64; // always points to the oldest entry
  };

  public func new(max_storage : Nat64) : FileSystem {
    return {
      var files = WriteableBand.new();
      var file_index = 1;
      var directories = Map.new<Blob, Directory>();
      var max_storage = max_storage;
      var current_storage = 0;
      var first_entry_offset = 0;
      var end_offset = 0;
      var next_entry_offset = null; // no entries to remove in empty filesystem
    };
  };

  public func set_max_storage(fs : FileSystem, max_storage : Nat64) {
    fs.max_storage := max_storage;
  };

  public func create_directory(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, parent_id : ?Blob) : Result.Result<(), Text> {
    if (directory_id.size() != 32) {
      return #err("directory_id must be 32 bytes");
    };

    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) {
        // passthrough
      };
      case (?value) {
        return #err("directory already exists");
      };
    };

    let directory : Directory = {
      id = directory_id;
      name_ciphertext = name_ciphertext;
      parent_id = parent_id;
      timestamp = Nat32.fromNat(abs(now()) / 1_000_000_000);
      child_directories = [];
      child_files = [];
    };

    Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, directory);

    // Add to parent's child_directories if parent exists
    switch (parent_id) {
      case (null) {};
      case (?parent) {
        switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, parent)) {
          case (null) {
            return #err("parent directory not found");
          };
          case (?parent_dir) {
            let updated_parent : Directory = {
              id = parent_dir.id;
              name_ciphertext = parent_dir.name_ciphertext;
              parent_id = parent_dir.parent_id;
              timestamp = parent_dir.timestamp;
              child_directories = Array.append(parent_dir.child_directories, [directory_id]);
              child_files = parent_dir.child_files;
            };
            Map.set<Blob, Directory>(fs.directories, Map.bhash, parent, updated_parent);
          };
        };
      };
    };

    return #ok();
  };

  public func add_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, ciphertext : Blob) : Result.Result<Nat32, Text> {
    if (directory_id.size() != 32) {
      return #err("directory_id must be 32 bytes");
    };
    if (content_hash.size() != 32) {
      return #err("content_hash must be 32 bytes");
    };
    
    // Check if file already exists by searching through all directories
    for ((dir_id, directory) in Map.entries(fs.directories)) {
      for (file in directory.child_files.vals()) {
        if (Blob.equal(file.content_hash, content_hash)) {
          return #ok(file.id);
        };
      };
    };
    
    // Check if directory exists
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found") };
      case (?directory) { /* passthrough */ };
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

    // Write file content
    let content_offset = fs.end_offset;
    WriteableBand.writeBlob(fs.files, content_offset, ciphertext);
    fs.end_offset += file_size;
    // Write file entry
    let entry_offset = fs.end_offset;
    WriteableBand.appendNat32(fs.files, fs.file_index);
    WriteableBand.appendNat32(fs.files, Nat32.fromNat(abs(now()) / 1_000_000_000));
    WriteableBand.appendBlob(fs.files, directory_id);
    WriteableBand.appendBlob(fs.files, name_ciphertext);
    WriteableBand.appendBlob(fs.files, content_hash);
    WriteableBand.appendNat64(fs.files, file_size);
    WriteableBand.appendNat32(fs.files, 1); // finalized
    WriteableBand.appendNat32(fs.files, 0); // reserved
    fs.end_offset += file_entry_size;
    fs.current_storage += total_size;

    // Set next_entry_offset to point to the first entry when adding the first file
    if (fs.next_entry_offset == null) {
      fs.next_entry_offset := ?entry_offset;
    };

    // Create File struct
    let file : File = {
      id = fs.file_index;
      timestamp = Nat32.fromNat(abs(now()) / 1_000_000_000);
      name_ciphertext = name_ciphertext;
      content_hash = content_hash;
      offset = content_offset;
      size = file_size;
      finalized = true;
    };

    // Update directory's child_files
    let directory = Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
    switch (directory) {
      case (null) { return #err("directory not found during update") };
      case (?dir) {
        let updated_directory : Directory = {
          id = dir.id;
          name_ciphertext = dir.name_ciphertext;
          parent_id = dir.parent_id;
          timestamp = dir.timestamp;
          child_directories = dir.child_directories;
          child_files = Array.append(dir.child_files, [file]);
        };
        Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
      };
    };
    fs.file_index += 1;
    return #ok(fs.file_index - 1);
  };

  public func write_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, ciphertext : Blob) : Result.Result<Nat32, Text> {
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

  // Helper function to find file by content_hash across all directories
  private func find_file_by_content_hash(fs : FileSystem, content_hash : Blob) : ?(File, Blob) {
    for ((dir_id, directory) in Map.entries(fs.directories)) {
      for (file in directory.child_files.vals()) {
        if (Blob.equal(file.content_hash, content_hash)) {
          return ?(file, dir_id);
        };
      };
    };
    return null;
  };

  public func delete_file(fs : FileSystem, content_hash : Blob) : Result.Result<(), Text> {
    switch (find_file_by_content_hash(fs, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?(file, directory_id)) {
        let entry_offset = get_file_entry_offset(fs, file.id);
        let size = WriteableBand.readNat64(fs.files, entry_offset + 104);

        // Remove from directory's child_files list
        switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
          case (null) {
            return #err("directory not found during delete");
          };
          case (?dir) {
            let updated_directory : Directory = {
              id = dir.id;
              name_ciphertext = dir.name_ciphertext;
              parent_id = dir.parent_id;
              timestamp = dir.timestamp;
              child_directories = dir.child_directories;
              child_files = Array.filter<File>(dir.child_files, func(f : File) : Bool { f.id != file.id });
            };
            Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
          };
        };

        // Mark entry as deleted by setting timestamp to 0
        WriteableBand.writeNat32(fs.files, entry_offset + 4, 0);

        // Update storage counters
        let total_size = size + file_entry_size;
        if (fs.current_storage >= total_size) {
          fs.current_storage -= total_size;
        } else {
          fs.current_storage := 0;
        };

        return #ok();
      };
    };
  };

  public func allocate_file(fs : FileSystem, directory_id : Blob, name_ciphertext : Blob, content_hash : Blob, size : Nat64) : Result.Result<Nat32, Text> {
    if (directory_id.size() != 32) {
      return #err("directory_id must be 32 bytes");
    };
    if (content_hash.size() != 32) {
      return #err("content_hash must be 32 bytes");
    };
    if (size == 0) {
      return #err("size must be greater than 0");
    };

    // Check if file already exists by searching through all directories
    for ((dir_id, directory) in Map.entries(fs.directories)) {
      for (file in directory.child_files.vals()) {
        if (Blob.equal(file.content_hash, content_hash)) {
          return #ok(file.id);
        };
      };
    };

    // Check if directory exists
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found") };
      case (?directory) { /* passthrough */ };
    };

    let total_size = size + file_entry_size;
    ensureRingBufferSpace(fs, total_size);

    // Wrap if needed
    if (fs.end_offset + total_size > fs.max_storage) {
      fs.end_offset := 0;
    };

    // Write file entry first with finalized = 0
    let entry_offset = fs.end_offset + size; // content comes before entry
    WriteableBand.writeNat32(fs.files, entry_offset, fs.file_index);
    WriteableBand.writeNat32(fs.files, entry_offset + 4, Nat32.fromNat(abs(now()) / 1_000_000_000));
    WriteableBand.writeBlob(fs.files, entry_offset + 8, directory_id);
    WriteableBand.writeBlob(fs.files, entry_offset + 40, name_ciphertext);
    WriteableBand.writeBlob(fs.files, entry_offset + 72, content_hash);
    WriteableBand.writeNat64(fs.files, entry_offset + 104, size);
    WriteableBand.writeNat32(fs.files, entry_offset + 112, 0); // not finalized
    WriteableBand.writeNat32(fs.files, entry_offset + 116, 0); // reserved

    fs.end_offset += total_size;
    fs.current_storage += total_size;

    // Create File struct for unfinalized file
    let file : File = {
      id = fs.file_index;
      timestamp = Nat32.fromNat(abs(now()) / 1_000_000_000);
      name_ciphertext = name_ciphertext;
      content_hash = content_hash;
      offset = fs.end_offset; // content offset (before we add total_size)
      size = size;
      finalized = false;
    };

    // Add file to directory's child_files even though it's not finalized
    let directory = Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
    switch (directory) {
      case (null) { return #err("directory not found during allocate") };
      case (?dir) {
        let updated_directory : Directory = {
          id = dir.id;
          name_ciphertext = dir.name_ciphertext;
          parent_id = dir.parent_id;
          timestamp = dir.timestamp;
          child_directories = dir.child_directories;
          child_files = Array.append(dir.child_files, [file]);
        };
        Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
      };
    };

    let result_id = fs.file_index;
    fs.file_index += 1;
    return #ok(result_id);
  };

  public func write_file_chunk(fs : FileSystem, content_hash : Blob, chunk_offset : Nat64, chunk : Blob) : Result.Result<(), Text> {
    switch (find_file_by_content_hash(fs, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?(file, directory_id)) {
        if (file.finalized) {
          return #err("file is already finalized");
        };

        if (chunk_offset + Nat64.fromNat(chunk.size()) > file.size) {
          return #err("chunk out of bounds");
        };

        // Use the file's stored offset directly
        let content_offset = file.offset + chunk_offset;
        WriteableBand.writeBlob(fs.files, content_offset, chunk);
        return #ok();
      };
    };
  };

  public func finalize_file(fs : FileSystem, content_hash : Blob) : Result.Result<(), Text> {
    switch (find_file_by_content_hash(fs, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?(file, directory_id)) {
        let entry_offset = get_file_entry_offset(fs, file.id);

        // Check if already finalized
        let already_finalized = WriteableBand.readNat32(fs.files, entry_offset + 112) == 1;
        if (already_finalized) {
          return #ok(); // Already finalized, nothing to do
        };

        // Mark as finalized
        WriteableBand.writeNat32(fs.files, entry_offset + 112, 1);

        // Update directory's child_files only if not already finalized
        let directory = Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
        switch (directory) {
          case (null) { return #err("directory not found during finalize") };
          case (?dir) {
            // Update the file in the directory to mark it as finalized
            let updated_files = Array.map<File, File>(dir.child_files, func(f : File) : File {
              if (f.id == file.id) {
                {
                  id = f.id;
                  timestamp = f.timestamp;
                  name_ciphertext = f.name_ciphertext;
                  content_hash = f.content_hash;
                  offset = f.offset;
                  size = f.size;
                  finalized = true;
                }
              } else {
                f
              }
            });
            let updated_directory : Directory = {
              id = dir.id;
              name_ciphertext = dir.name_ciphertext;
              parent_id = dir.parent_id;
              timestamp = dir.timestamp;
              child_directories = dir.child_directories;
              child_files = updated_files;
            };
            Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
          };
        };

        return #ok();
      };
    };
  };

  public func read_file_chunk(fs : FileSystem, content_hash : Blob, chunk_offset : Nat64, chunk_size : Nat) : Result.Result<Blob, Text> {
    switch (find_file_by_content_hash(fs, content_hash)) {
      case (null) {
        return #err("file not found");
      };
      case (?(file, directory_id)) {
        if (not file.finalized) {
          return #err("file is not finalized");
        };

        if (chunk_offset + Nat64.fromNat(chunk_size) > file.size) {
          return #err("chunk out of bounds");
        };

        // Use the file's stored offset directly
        let content_offset = file.offset + chunk_offset;
        let chunk = WriteableBand.readBlob(fs.files, content_offset, chunk_size);
        return #ok(chunk);
      };
    };
  };

  public func read_file_content(fs : FileSystem, file : File) : Blob {
    return WriteableBand.readBlob(fs.files, file.offset, Nat64.toNat(file.size));
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
      case (?offset) {
        // Read file entry to get content hash for removal from index
        let file_id = WriteableBand.readNat32(fs.files, offset);
        let directory_id = WriteableBand.readBlob(fs.files, offset + 8, 32);
        let content_hash = WriteableBand.readBlob(fs.files, offset + 72, 32);
        let size = WriteableBand.readNat64(fs.files, offset + 104);
        let finalized = WriteableBand.readNat32(fs.files, offset + 112) == 1;

        // Remove from directory's file entries
        switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
          case (null) {};
          case (?dir) {
            let updated_directory : Directory = {
              id = dir.id;
              name_ciphertext = dir.name_ciphertext;
              parent_id = dir.parent_id;
              timestamp = dir.timestamp;
              child_directories = dir.child_directories;
              child_files = Array.filter<File>(dir.child_files, func(f : File) : Bool { f.id != file_id });
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

        // Mark entry as empty
        WriteableBand.writeNat32(fs.files, offset + 4, 0); // timestamp = 0 marks as empty
        // For now, just set to null. It will be recalculated when needed.
        // The complex next-entry calculation is tricky with the [content][entry] layout.
        fs.next_entry_offset := null;
      };
    };
  };

  public func get_file_by_hash(fs : FileSystem, content_hash : Blob) : Result.Result<File, Text> {
    switch (find_file_by_content_hash(fs, content_hash)) {
      case (null) { #err("file not found") };
      case (?(file, directory_id)) { #ok(file) };
    };
  };

  public func get_file_by_id(fs : FileSystem, file_id : Nat32) : File {
    // Search through all directories to find the file
    for ((dir_id, directory) in Map.entries(fs.directories)) {
      for (file in directory.child_files.vals()) {
        if (file.id == file_id) {
          return file;
        };
      };
    };
    // If not found in directories, fall back to reading from WriteableBand
    let offset = get_file_entry_offset(fs, file_id);
    return get_file_by_offset(fs, offset);
  };

  private func get_file_entry_offset(fs : FileSystem, file_id : Nat32) : Nat64 {
    assert (file_id > 0);
    // Fallback to sequential calculation since we removed the offset map
    return Nat64.fromNat32(file_id - 1) * file_entry_size;
  };

  private func get_file_by_offset(fs : FileSystem, _offset : Nat64) : File {
    var offset = _offset;
    let id = WriteableBand.readNat32(fs.files, offset);
    offset += 4;
    let timestamp = WriteableBand.readNat32(fs.files, offset);
    offset += 4;
    let directory_id = WriteableBand.readBlob(fs.files, offset, 32);
    offset += 32;
    let name_ciphertext = WriteableBand.readBlob(fs.files, offset, 32);
    offset += 32;
    let content_hash = WriteableBand.readBlob(fs.files, offset, 32);
    offset += 32;
    let size = WriteableBand.readNat64(fs.files, offset);
    offset += 8;
    let finalized = WriteableBand.readNat32(fs.files, offset) == 1;
    offset += 4;
    let reserved = WriteableBand.readNat32(fs.files, offset);

    // Calculate content offset (content is stored before the entry)
    let content_offset = _offset - size;

    return {
      id = id;
      timestamp = timestamp;
      name_ciphertext = name_ciphertext;
      content_hash = content_hash;
      offset = content_offset;
      size = size;
      finalized = finalized;
    };
  };

  public func get_directory(fs : FileSystem, directory_id : Blob) : ?Directory {
    return Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
  };

  public func get_files_in_directory(fs : FileSystem, directory_id : Blob) : [File] {
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { [] };
      case (?directory) {
        Array.filter<File>(directory.child_files, func(file : File) : Bool {
          file.finalized
        });
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

  public func get_usage(fs : FileSystem) : Nat64 {
    return fs.current_storage;
  };

  public func get_max_usage(fs : FileSystem) : Nat64 {
    return fs.max_storage;
  };

  public func get_file_count(fs : FileSystem) : Nat {
    var count = 0;
    for ((dir_id, directory) in Map.entries(fs.directories)) {
      count += directory.child_files.size();
    };
    return count;
  };

  public func get_directory_count(fs : FileSystem) : Nat {
    return Map.size(fs.directories);
  };
};
