class GitFileItem {
  final String path;
  final String status; // 'M', 'U', 'D', 'A', 'R', 'S'
  final bool isStaged;
  final String? oldPath;

  const GitFileItem({
    required this.path,
    required this.status,
    this.isStaged = false,
    this.oldPath,
  });

  factory GitFileItem.fromJson(Map<String, dynamic> json) {
    return GitFileItem(
      path: json['path'] as String? ?? '',
      status: json['status'] as String? ?? 'M',
      isStaged: json['is_staged'] as bool? ?? false,
      oldPath: json['old_path'] as String?,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'M':
        return 'Modified';
      case 'U':
        return 'Untracked';
      case 'D':
        return 'Deleted';
      case 'A':
        return 'Added';
      case 'R':
        return 'Renamed';
      case 'S':
        return 'Staged';
      default:
        return status;
    }
  }

  String get fileName => path.split('/').lastOrNull ?? path;
  String get dirName {
    final idx = path.lastIndexOf('/');
    return idx != -1 ? path.substring(0, idx) : '';
  }
}

class GitStatusData {
  final bool isRepo;
  final String branch;
  final String? tracking;
  final int ahead;
  final int behind;
  final bool isClean;
  final List<GitFileItem> staged;
  final List<GitFileItem> unstaged;
  final List<GitFileItem> untracked;
  final String? lastCommitHash;
  final String? lastCommitMessage;
  final String? lastCommitAuthor;
  final String? lastCommitDate;

  const GitStatusData({
    this.isRepo = false,
    this.branch = 'HEAD',
    this.tracking,
    this.ahead = 0,
    this.behind = 0,
    this.isClean = true,
    this.staged = const [],
    this.unstaged = const [],
    this.untracked = const [],
    this.lastCommitHash,
    this.lastCommitMessage,
    this.lastCommitAuthor,
    this.lastCommitDate,
  });

  int get totalChangesCount =>
      staged.length + unstaged.length + untracked.length;

  factory GitStatusData.fromJson(Map<String, dynamic> json) {
    return GitStatusData(
      isRepo: json['is_repo'] as bool? ?? false,
      branch: json['branch'] as String? ?? 'HEAD',
      tracking: json['tracking'] as String?,
      ahead: json['ahead'] as int? ?? 0,
      behind: json['behind'] as int? ?? 0,
      isClean: json['is_clean'] as bool? ?? true,
      staged: ((json['staged'] as List<dynamic>?) ?? [])
          .map((e) => GitFileItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      unstaged: ((json['unstaged'] as List<dynamic>?) ?? [])
          .map((e) => GitFileItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      untracked: ((json['untracked'] as List<dynamic>?) ?? [])
          .map((e) => GitFileItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastCommitHash: json['last_commit_hash'] as String?,
      lastCommitMessage: json['last_commit_message'] as String?,
      lastCommitAuthor: json['last_commit_author'] as String?,
      lastCommitDate: json['last_commit_date'] as String?,
    );
  }
}
