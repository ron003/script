#!/bin/bash
set -e
#set -uo pipefail

if [ "$1" == "--help" -o "$1" == "-h" -o "$1" == "-?" ];then
    echo
    echo "Usage: $0"
    echo
    exit
fi
set -u

coredaq_ver=coredaq-v4.5.8
TEST_ROOT=test_root

mkdir $TEST_ROOT && cd $TEST_ROOT

git clone git@github.com:DUNE-DAQ/daq-buildtools -b $coredaq_ver # normally at /cvmfs/...
git clone git@github.com:DUNE-DAQ/daq-release    -b $coredaq_ver

mkdir externals; install_dir=$PWD/externals


# The 4 externals repos: Catch2, cetmodules, cetlib-except, cetlib

git clone https://github.com/catchorg/Catch2 -b v2.13.10  #v3.12.0
cd Catch2; mkdir build; cd build
cmake -DCMAKE_INSTALL_PREFIX=$install_dir .. && make -j$(nproc) && make install
cd ../..

git clone https://github.com/FNALssi/cetmodules -b 3.18.00
cd cetmodules;mkdir build;cd build
cmake -DBUILD_DOCS=0 -DCMAKE_INSTALL_PREFIX=$PWD ..;make -j$(nproc) && make install
cetmodules=$PWD;cd ../..

git clone git@github.com:art-framework-suite/cetlib-except -b v1_07_04
cd cetlib-except; mkdir build; cd build
CMAKE_PREFIX_PATH=$cetmodules:$install_dir/lib/cmake/Catch2 \
cmake -DCMAKE_INSTALL_PREFIX=$install_dir .. && make -j$(nproc)
mkdir -p CMakeFiles/Export/lib/cetlib_except  # deal with uber new cmake
ln -s ../../cba13e0e966cbf40c2dc2e28d3a59f59 CMakeFiles/Export/lib/cetlib_except/cmake
make install
cd ../..

git clone git@github.com:art-framework-suite/cetlib -b v3_18_01; cd cetlib
patch -p1 <../daq-release/spack-repos/externals/packages/cetlib/cetlib_lite.patch
mkdir build; cd build
CMAKE_PREFIX_PATH=$cetmodules:$install_dir/lib/cmake/Catch2:$install_dir/lib/cetlib_except/cmake \
cmake -DBUILD_TESTING=FALSE -DCMAKE_INSTALL_PREFIX=$install_dir ..; make -j$(nproc)
mkdir -p CMakeFiles/Export/lib/cetlib # deal with uber new cmake
ln -s ../../d6cf62c7c6d24d3aa088679a86b1376f CMakeFiles/Export/lib/cetlib/cmake
make install
cd ../..

# DONE with 4 "externals"


mkdir install
echo ". daq-buildtools/env.sh
#dbt-workarea-env
export DBT_AREA_ROOT=$PWD

#externals:
echo \":\$LD_LIBRARY_PATH:\" | grep -q \":$PWD/externals/lib\" || LD_LIBRARY_PATH=$PWD/externals/lib:\$LD_LIBRARY_PATH

for dd in \`find install -name bin\`;do
  echo \":\$PATH:\" | grep -q \":$PWD/\$dd:\" || { echo Adding \$dd to PATH; PATH=$PWD/\$dd:\$PATH;}
done
for dd in \`find install -name lib\`;do
  echo \":\$LD_LIBRARY_PATH:\" | grep -q \":$PWD/\$dd:\" || LD_LIBRARY_PATH=$PWD/\$dd:\$LD_LIBRARY_PATH
done
for dd in \`find install -name python\`;do
  echo \":\$PYTHONPATH:\" | grep -q \":$PWD/\$dd:\" || { echo Adding \$dd to PYTHONPATH; export PYTHONPATH=$PWD/\$dd:\$PYTHONPATH;}
done
for dd in \`find install -name share\`;do
   export \$(basename \`dirname \$dd\` | tr 'a-z-' 'A-Z_')_SHARE=$PWD/\$dd
done
test -d .venv || python3 -m venv --prompt dbt .venv
unset _OLD_VIRTUAL_PATH # a tricky detail - partial \"deactivate\"
. .venv/bin/activate"'

dbt-build() {
    pushd $DBT_AREA_ROOT/build
    logfile=build_attempt_`date|sed "s/[ :][ :]*/_/g"`.log

    CMAKE_PREFIX_PATH=\
$DBT_AREA_ROOT/.venv/lib/python3.10/site-packages/pybind11:\
$DBT_AREA_ROOT/externals/lib/cetlib/cmake:\
$DBT_AREA_ROOT/externals/lib/cetlib_except/cmake:\
$DBT_AREA_ROOT/externals/share/TRACE/cmake

    CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
cmake -DCMAKE_MODULE_PATH=$DBT_ROOT/cmake -DCMAKE_INSTALL_PREFIX=$DBT_AREA_ROOT/install ../sourcecode 2>&1 | tee ../log/$logfile

    ( make -j$(nproc) && make install ) 2>&1 | tee -a ../log/$logfile

    echo log file at $DBT_AREA_ROOT/log/$logfile
    popd
}
' >env.sh

touch dbt-workarea-constants.sh

echo
echo 'Install some sourcecode in the sourcecode subdirectory...'
echo

mkdir sourcecode; cd sourcecode
cp ../daq-buildtools/configs/CMakeLists.txt .
cp ../daq-release/configs/fddaq/fddaq-v4.4.8/dbt-build-order.cmake .
git clone git@github.com:DUNE-DAQ/daq-cmake      -b $coredaq_ver
git clone git@github.com:DUNE-DAQ/ers            -b ron/address_warnings #$coredaq_ver
git clone git@github.com:DUNE-DAQ/logging        -b ron/address_warnings #$coredaq_ver
#git clone git@github.com:DUNE-DAQ/detchannelmaps -b $coredaq_ver
git clone git@github.com:ron003/detchannelmaps -b ron/run_channel_map_api

git clone git@github.com:art-daq/trace -b develop #v3_17_14  # v3_20_00
grep -q trace dbt-build-order.cmake || sed -i '/daq-cmake/a\
                "trace"' dbt-build-order.cmake

git clone git@github.com:ron003/icebergchanneltowire 
grep -q icebergchanneltowire dbt-build-order.cmake || sed -i '/trace/a\
                "icebergchanneltowire"' dbt-build-order.cmake
cd ..


echo 'Executinging . env.sh'
. env.sh   # needs to see ./dbt-workarea-constants.sh; get my dbt-build

pip install pybind11

cd $DBT_AREA_ROOT
mkdir build
mkdir log
dbt-build
echo "Now: cd $TEST_ROOT; . ./env.sh"

