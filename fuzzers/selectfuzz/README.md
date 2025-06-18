To build selectfuzz dockers, replace 'FROM ubuntu:22.04' with 'FROM ubuntu:16.04' in Dockerfile. 
18.04 might also work but I have not tested yet. The fuzzer cannot be compiled from 22.04 or above.

selectfuzz depends on llvm-4.0 tool chain which is too old to build openssl and php.