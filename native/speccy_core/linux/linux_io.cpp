// Linux implementations of the platform hooks the portable engine leaves to
// each host. The Android fork provides these from Java; this headless build
// supplies them here. Same shim as SimpleSpeccy's build/linux/linux_io.cpp.
#include <sys/stat.h>
#include <sys/types.h>
#include <cerrno>

namespace xIo
{
bool MkDir(const char* path)
{
    if(::mkdir(path, 0755) == 0)
        return true;
    return errno == EEXIST;   // already there counts as success
}
}
