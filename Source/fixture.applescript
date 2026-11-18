on run argv
    with timeout of 120 seconds
        tell application "/Applications/Keynote Creator Studio.app"
            set d to make new document
            tell d
                set width to 1920
                set height to 1080
                set s to slide 1
                set object text of default title item of s to "大图与讲稿，一起好读"
                set object text of default body item of s to "Keynote Reader 本地导出验证"
                set presenter notes of s to "这是从 Keynote 直接读取的演讲者注释。中文、English、数字 2026，以及标点：‘引号’、&、< >，都应保留。" & return & return & "图片保持原比例，文字可以选择和复制。短注释不再被大片留白包围。"
                set s2 to make new slide at end of slides
                set object text of default title item of s2 to "长注释自动续页"
                set t to ""
                repeat with i from 1 to 55
                    set t to t & "第" & i & "段：这是长文分页测试。每一段都应完整保留，不能漏字、重叠或者截断。This is a pagination test with Unicode 中文。" & return
                end repeat
                set presenter notes of s2 to t & "END-OF-LONG-NOTES-完"
                set s3 to make new slide at end of slides
                set object text of default title item of s3 to "HIDDEN-LAST"
                set presenter notes of s3 to "HIDDEN-NOTES-LAST"
                set skipped of s3 to true
                set h1 to make new slide at beginning of slides
                set object text of default title item of h1 to "HIDDEN-FIRST"
                set presenter notes of h1 to "HIDDEN-NOTES-FIRST"
                set skipped of h1 to true
                set h2 to make new slide at before s2
                set object text of default title item of h2 to "HIDDEN-MIDDLE"
                set presenter notes of h2 to "HIDDEN-NOTES-MIDDLE"
                set skipped of h2 to true
            end tell
            save d in POSIX file (item 1 of argv)
            close d saving no
        end tell
    end timeout
end run
