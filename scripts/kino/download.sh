#!/usr/bin/env bash

if [ -z "$1" ]; then
    echo "Usage: $0 <url>"
    exit 1
fi

url=$1
id=$(echo "$url" | rev | cut -d '/' -f1 | rev | cut -d '-' -f1)
echo "ID: $id"

common_headers=(
    -H "accept-language: en-US,en;q=0.9,ru;q=0.8,be;q=0.7,uk;q=0.6"
    -H "cache-control: max-age=0"
    -H "priority: u=0, i"
    -H 'sec-ch-ua: "Google Chrome";v="129", "Not=A?Brand";v="8", "Chromium";v="129"'
    -H 'sec-ch-ua-mobile: ?0'
    -H 'sec-ch-ua-platform: "Linux"'
    -H "sec-fetch-dest: document"
    -H "sec-fetch-mode: navigate"
    -H "sec-fetch-site: same-origin"
    -H "sec-fetch-user: ?1"
    -H "upgrade-insecure-requests: 1"
    -H "user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
)

page_content=$(curl -s "${common_headers[@]}" "$url")

video_url=$(echo "$page_content" | grep -oP '<link itemprop="video" value="\K[^"]+')
if [ -z "$video_url" ]; then
    echo "No <link> tag with itemprop='video' found"
    echo "Please enter a video URL:"
    read -r video_url
fi

echo "Found video URL: $video_url"

video_page_content=$(curl -s "${common_headers[@]}" "$video_url")

m3u8_link=$(echo "$video_page_content" | grep -oP '(https.*?\.m3u8)')
if [ -z "$m3u8_link" ]; then
    echo "No .m3u8 link found on the page"
    exit 1
fi

echo "Found .m3u8 link: $m3u8_link"

m3u8_content=$(curl -s "${common_headers[@]}" "$m3u8_link")
best_quality_link=$(echo "$m3u8_content" | awk -F: '/#EXT-X-STREAM-INF/ {getline; print $0}' | sort -Vr | head -n 1)

if [ -z "$best_quality_link" ]; then
    echo "No stream links found"
    exit 1
fi

echo "Highest quality stream link: $best_quality_link"

m3u8_content=$(curl -s "${common_headers[@]}" "$best_quality_link")

output_dir="video_segments"
mkdir -p "$output_dir"

echo "Parsing segment URLs from index.m3u8..."
echo "$m3u8_content" | grep -v 'EXT' >segment_urls.txt

echo "Downloading segments in parallel..."
xargs -P "$(nproc)" -I {} bash -c '
  segment_name=$(basename {});
  if [[ -f "'$output_dir'/$segment_name" ]]; then
    echo "$segment_name already exists, skipping download.";
  else
    echo "Downloading $segment_name";
    curl -f -s -o "'$output_dir'/$segment_name" "{}";
  fi
' <segment_urls.txt

output_video="kino.avi"
echo "Combining all segments into $output_video..."

cat $(ls $output_dir/segment*.ts | sort -V) >"$output_video"

echo "Download and combination completed!"

echo "Do you want to move the video to the ~/movies folder? (y/n): "
read -r move_response

if [[ "$move_response" == "y" ]]; then
    movie="$HOME/movies/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10).avi"
    mv "$output_video" "$movie"
    echo "Video moved to $movie"
else
    echo "Video remains in the current directory."
fi

rm -rf "$output_dir"
rm segment_urls.txt
