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
    directory_id : Blob;
    name_hash : Blob; // encrypted filename hash
    content_hash : Blob;
    ciphertext : Blob;
    size : Nat64;
  };

  public type Directory = {
    id : Blob;
    name_hash : Blob; // encrypted directory name
    parent_id : ?Blob; // null for root
    timestamp : Nat32;
    child_directories : [Blob];
    child_files : [Nat32];
  };

  let file_entry_size : Nat64 = 116; // 4 + 4 + 32 + 32 + 32 + 8 + 4; // id + timestamp + directory_id + name_hash + content_hash + size + finalized

  type FileEntry = {
    var min_file_id : Nat32;
    var max_file_id : Nat32;
    var file_count : Nat32;
  };

  public type FileSystem = {
    var files : WriteableBand.WriteableBand; // ring buffer for file contents
    var file_index : Nat32;
    var directories : Map.Map<Blob, Directory>;
    var file_index_map : Map.Map<Blob, Nat32>; // content_hash -> file_id
    var file_id_to_offset : Map.Map<Nat32, Nat64>; // file_id -> entry_offset
    var directory_index : Map.Map<Blob, Blob>; // name_hash -> directory_id
    var directory_file_entries : Map.Map<Blob, FileEntry>; // directory_id -> FileEntry
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
      var file_index_map = Map.new<Blob, Nat32>();
      var file_id_to_offset = Map.new<Nat32, Nat64>();
      var directory_index = Map.new<Blob, Blob>();
      var directory_file_entries = Map.new<Blob, FileEntry>();
      var max_storage = max_storage;
      var current_storage = 0;
      var first_entry_offset = 0;
      var end_offset = 0;
      var next_entry_offset = ?0; // always start at 0
    };
  };

  public func set_max_storage(fs : FileSystem, max_storage : Nat64) {
    fs.max_storage := max_storage;
  };

  public func create_directory(fs : FileSystem, directory_id : Blob, name_hash : Blob, parent_id : ?Blob) : Result.Result<(), Text> {
    if (directory_id.size() != 32) {
      return #err("directory_id must be 32 bytes");
    };

    if (name_hash.size() != 32) {
      return #err("name_hash must be 32 bytes");
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
      name_hash = name_hash;
      parent_id = parent_id;
      timestamp = Nat32.fromNat(abs(now()) / 1_000_000_000);
      child_directories = [];
      child_files = [];
    };

    Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, directory);
    Map.set<Blob, Blob>(fs.directory_index, Map.bhash, name_hash, directory_id);

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
              name_hash = parent_dir.name_hash;
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

  public func add_file(fs : FileSystem, directory_id : Blob, name_hash : Blob, content_hash : Blob, ciphertext : Blob) : Result.Result<Nat32, Text> {
    if (directory_id.size() != 32) {
      return #err("directory_id must be 32 bytes");
    };
    if (name_hash.size() != 32) {
      return #err("name_hash must be 32 bytes");
    };
    if (content_hash.size() != 32) {
      return #err("content_hash must be 32 bytes");
    };
    // Check if file already exists
    switch (Map.get<Blob, Nat32>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) { /* passthrough */ };
      case (?value) { return #ok(value); };
    };
    // Check if directory exists
    switch (Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id)) {
      case (null) { return #err("directory not found"); };
      case (?directory) { /* passthrough */ };
    };
    let file_size = Nat64.fromNat(ciphertext.size());
    let total_size = file_size + file_entry_size;
    ensureRingBufferSpace(fs, total_size);
    // Wrap if needed
    if (fs.end_offset + total_size > fs.max_storage) {
      fs.end_offset := 0;
    }
    // Write file content
    let content_offset = fs.end_offset;
    WriteableBand.writeBlob(fs.files, content_offset, ciphertext);
    fs.end_offset += file_size;
    // Write file entry
    let entry_offset = fs.end_offset;
    WriteableBand.appendNat32(fs.files, fs.file_index);
    WriteableBand.appendNat32(fs.files, Nat32.fromNat(abs(now()) / 1_000_000_000));
    WriteableBand.appendBlob(fs.files, directory_id);
    WriteableBand.appendBlob(fs.files, name_hash);
    WriteableBand.appendBlob(fs.files, content_hash);
    WriteableBand.appendNat64(fs.files, file_size);
    WriteableBand.appendNat32(fs.files, 1); // finalized
    fs.end_offset += file_entry_size;
    fs.current_storage += total_size;
    // Update file index
    Map.set<Blob, Nat32>(fs.file_index_map, Map.bhash, content_hash, fs.file_index);
    Map.set<Nat32, Nat64>(fs.file_id_to_offset, Map.n32hash, fs.file_index, entry_offset);
    // Update directory file entries (unchanged)
    let prev_entry = Map.get<Blob, FileEntry>(fs.directory_file_entries, Map.bhash, directory_id);
    let new_entry : FileEntry = switch (prev_entry) {
      case (null) { { var min_file_id = fs.file_index; var max_file_id = fs.file_index; var file_count = 1; }; };
      case (?value) { { var min_file_id = value.min_file_id; var max_file_id = fs.file_index; var file_count = value.file_count + 1; }; };
    };
    Map.set<Blob, FileEntry>(fs.directory_file_entries, Map.bhash, directory_id, new_entry);
    // Update directory's child_files (unchanged)
    let directory = Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
    switch (directory) {
      case (null) { return #err("directory not found during update"); };
      case (?dir) {
        let updated_directory : Directory = {
          id = dir.id;
          name_hash = dir.name_hash;
          parent_id = dir.parent_id;
          timestamp = dir.timestamp;
          child_directories = dir.child_directories;
          child_files = Array.append(dir.child_files, [fs.file_index]);
        };
        Map.set<Blob, Directory>(fs.directories, Map.bhash, directory_id, updated_directory);
      };
    };
    fs.file_index += 1;
    return #ok(fs.file_index - 1);
  };

  private func ensureRingBufferSpace(fs : FileSystem, total_size : Nat64) {
    while (true) {
      let next_offset_val = switch (fs.next_entry_offset) { case null { 0 }; case (?v) { v } };
      let used = if (fs.end_offset >= next_offset_val) {
        fs.end_offset - next_offset_val
      } else {
        fs.max_storage - next_offset_val + fs.end_offset
      };
      if (fs.max_storage - used >= total_size) return;
      if (fs.next_entry_offset == null) return;
      remove_next_file_entry(fs);
      let next_offset_val2 = switch (fs.next_entry_offset) { case null { 0 }; case (?v) { v } };
      let used2 = if (fs.end_offset >= next_offset_val2) {
        fs.end_offset - next_offset_val2
      } else {
        fs.max_storage - next_offset_val2 + fs.end_offset
      };
      if (used2 == used) return; // avoid infinite loop
    }
  };

  private func remove_next_file_entry(fs : FileSystem) {
    switch (fs.next_entry_offset) {
      case (null) { return; };
      case (?offset) {
        // Read file entry to get content hash for removal from index
        let file_id = WriteableBand.readNat32(fs.files, offset);
        let directory_id = WriteableBand.readBlob(fs.files, offset + 8, 32);
        let content_hash = WriteableBand.readBlob(fs.files, offset + 72, 32);
        let size = WriteableBand.readNat64(fs.files, offset + 104);
        // Remove from file index
        Map.delete<Blob, Nat32>(fs.file_index_map, Map.bhash, content_hash);
        Map.delete<Nat32, Nat64>(fs.file_id_to_offset, Map.n32hash, file_id);
        // Update directory file entries
        switch (Map.get<Blob, FileEntry>(fs.directory_file_entries, Map.bhash, directory_id)) {
          case (null) {};
          case (?entry) {
            if (entry.file_count > 1) {
              let updated_entry : FileEntry = {
                var min_file_id = entry.min_file_id + 1;
                var max_file_id = entry.max_file_id;
                var file_count = entry.file_count - 1;
              };
              Map.set<Blob, FileEntry>(fs.directory_file_entries, Map.bhash, directory_id, updated_entry);
            } else {
              Map.delete<Blob, FileEntry>(fs.directory_file_entries, Map.bhash, directory_id);
            };
          };
        };
        // Mark entry as empty
        WriteableBand.writeNat32(fs.files, offset + 4, 0); // timestamp = 0 marks as empty
        // Advance next_entry_offset
        let next_offset = offset + size + file_entry_size;
        if (next_offset + file_entry_size > fs.max_storage) {
          fs.next_entry_offset := ?0;
        } else {
          fs.next_entry_offset := ?next_offset;
        };
      };
    };
  };

  public func get_file_by_hash(fs : FileSystem, content_hash : Blob) : Result.Result<File, Text> {
    switch (Map.get<Blob, Nat32>(fs.file_index_map, Map.bhash, content_hash)) {
      case (null) { #err("file not found") };
      case (?file_id) { #ok(get_file_by_id(fs, file_id)) };
    };
  };

  public func get_file_by_id(fs : FileSystem, file_id : Nat32) : File {
    let offset = get_file_entry_offset(fs, file_id);
    return get_file_by_offset(fs, offset);
  };

  private func get_file_entry_offset(fs : FileSystem, file_id : Nat32) : Nat64 {
    assert (file_id > 0);
    switch (Map.get<Nat32, Nat64>(fs.file_id_to_offset, Map.n32hash, file_id)) {
      case (null) {
        // Fallback to sequential calculation for backward compatibility
        return Nat64.fromNat32(file_id - 1) * file_entry_size;
      };
      case (?offset) {
        return offset;
      };
    };
  };

  private func get_file_by_offset(fs : FileSystem, _offset : Nat64) : File {
    var offset = _offset;
    let id = WriteableBand.readNat32(fs.files, offset);
    offset += 4;
    let timestamp = WriteableBand.readNat32(fs.files, offset);
    offset += 4;
    let directory_id = WriteableBand.readBlob(fs.files, offset, 32);
    offset += 32;
    let name_hash = WriteableBand.readBlob(fs.files, offset, 32);
    offset += 32;
    let content_hash = WriteableBand.readBlob(fs.files, offset, 32);
    offset += 32;
    let size = WriteableBand.readNat64(fs.files, offset);
    offset += 8;
    let finalized = WriteableBand.readNat32(fs.files, offset) == 1;

    // Calculate content offset (content is stored before the entry)
    let content_offset = _offset - size;

    let ciphertext = WriteableBand.readBlob(fs.files, content_offset, Nat64.toNat(size));

    return {
      id = id;
      timestamp = timestamp;
      directory_id = directory_id;
      name_hash = name_hash;
      content_hash = content_hash;
      ciphertext = ciphertext;
      size = size;
    };
  };

  public func get_directory(fs : FileSystem, directory_id : Blob) : ?Directory {
    return Map.get<Blob, Directory>(fs.directories, Map.bhash, directory_id);
  };

  public func get_directory_by_name(fs : FileSystem, name_hash : Blob) : ?Directory {
    switch (Map.get<Blob, Blob>(fs.directory_index, Map.bhash, name_hash)) {
      case (null) { null };
      case (?directory_id) { get_directory(fs, directory_id) };
    };
  };

  public func get_files_in_directory(fs : FileSystem, directory_id : Blob) : [File] {
    switch (Map.get<Blob, FileEntry>(fs.directory_file_entries, Map.bhash, directory_id)) {
      case (null) { [] };
      case (?entry) {
        let min_id = entry.min_file_id;
        let max_id = entry.max_file_id;
        let count = entry.file_count;
        
        if (count == 0) {
          return [];
        };

        // For now, we'll use the file ID approach since we need to maintain compatibility
        // with the FileEntry structure that stores file IDs
        let files = Array.init<File>(Nat32.toNat(count), get_file_by_id(fs, min_id));
        var current_id = min_id + 1;
        var index = 1;
        while (current_id <= max_id and index < Nat32.toNat(count)) {
          files[index] := get_file_by_id(fs, current_id);
          current_id += 1;
          index += 1;
        };
        Array.freeze(files);
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
    return Map.size(fs.file_index_map);
  };

  public func get_directory_count(fs : FileSystem) : Nat {
    return Map.size(fs.directories);
  };
}; 