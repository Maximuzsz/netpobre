class JellyfinSession {
  const JellyfinSession({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.userName,
    required this.serverName,
  });

  final String baseUrl;
  final String token;
  final String userId;
  final String userName;
  final String serverName;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'token': token,
    'userId': userId,
    'userName': userName,
    'serverName': serverName,
  };

  factory JellyfinSession.fromJson(Map<String, dynamic> json) =>
      JellyfinSession(
        baseUrl: json['baseUrl'] as String,
        token: json['token'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        serverName: json['serverName'] as String,
      );
}
