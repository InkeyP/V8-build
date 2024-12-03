VERSION=$1

sudo apt-get install -y \
    pkg-config \
    git \
    subversion \
    curl \
    wget \
    build-essential \
    python3 \
    xz-utils \
    zip

git config --global user.name "V8 Linux Builder"
git config --global user.email "v8.linux.builder@localhost"
git config --global core.autocrlf false
git config --global core.filemode false
git config --global color.ui true


cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH=$(pwd)/depot_tools:$PATH
gclient


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['linux']" >> .gclient
cd ~/v8/v8
echo "[*] install deps"
./build/install-build-deps.sh
git checkout 8cf17a14a78cc1276eb42e1b4bb699f705675530
gclient sync


echo "=====[ Building V8 ]====="
python3 ./tools/dev/v8gen.py x64.release -vv -- '
symbol_level=0
blink_symbol_level=0
is_debug = true
enable_nacl = false
dcheck_always_on = false
v8_enable_sandbox = true
'
ninja -C out.gn/x64.release -t clean
ninja -j8 -C out.gn/x64.release d8
