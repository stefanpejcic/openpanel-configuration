name: Update Cloudflare IPs

on:
  schedule:
    # Runs at 00:00 UTC every day
    - cron: '0 0 * * *'

jobs:
  update_cf_ips:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v3

    - name: Create get_cf_ips.sh script
      run: |
        mkdir -p .github/scripts
        echo '#!/bin/bash' > .github/scripts/get_cf_ips.sh
        echo 'curl -s https://www.cloudflare.com/ips-v4' >> .github/scripts/get_cf_ips.sh
        echo 'curl -s https://www.cloudflare.com/ips-v6' >> .github/scripts/get_cf_ips.sh
        chmod +x .github/scripts/get_cf_ips.sh

    - name: Run get_cf_ips.sh
      run: .github/scripts/get_cf_ips.sh > nginx/cloudflare.inc

    - name: Commit and push changes
      run: |
        git config --global user.name "github-actions[bot]"
        git config --global user.email "github-actions[bot]@users.noreply.github.com"
        git add nginx/cloudflare.inc
        git commit -m "Update Cloudflare IPs"
        git push
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        
