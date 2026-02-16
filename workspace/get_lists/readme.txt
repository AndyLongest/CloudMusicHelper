CloudMusic 导出工具（免 Python）

使用方法：
1) 关闭网易云音乐客户端。
2) 双击 run_export.bat。
3) 导出结果在 output 文件夹：
   - output\albums\*.txt（每个专辑一个 txt）
   - output\playlists\*.txt（每个歌单一个 txt）

说明：
- 仅支持 Windows。
- 工具会按“当前登录用户”自动查找数据库：
   %LOCALAPPDATA%\NetEase\CloudMusic\Library\webdb.dat
- 不同电脑、不同用户名都可自动适配。
