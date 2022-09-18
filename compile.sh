#!/usr/bin/env bash

package="example.com/dwmtmux"

package_split=(${package//\// })
package_name="dwmtmux"

platforms=("darwin/arm64" "darwin/amd64" "linux/amd64" "linux/arm64")

for platform in "${platforms[@]}"
do
    platform_split=(${platform//\// })
    GOOS=${platform_split[0]}
    GOARCH=${platform_split[1]}

    output_name=$package_name'-'$GOOS'-'$GOARCH

    if [ $GOOS = "windows" ]; then
        output_name+='.exe'
    fi
    echo env GOOS=$GOOS GOARCH=$GOARCH go build -tags $GOOS -o $output_name $package
    env GOOS=$GOOS GOARCH=$GOARCH go build -tags $GOOS -o $output_name $package 
    if [ $? -ne 0 ]; then
        echo 'An error has occurred! Aborting the script execution...'
        exit 1
    fi
done

mv dwmtmux-linux-arm64 dwmtmux-linux-aarch64
mv dwmtmux-linux-amd64 dwmtmux-linux-x86_64
