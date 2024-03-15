# provus-ci
## CI tools for Provus on Pantheon

Setup:
1.  Copy the following files and directory to the desired project to be added.
    * .travis 
    * .travis.yml
    * hosting
    * scripts
2. Edit both files inside hosting/pantheon/
    * pantheon.upstream.yml (PHP version)
    * pantheon.yml (PHP version)
3. Make sure the build_step = true on both pantheon.yml and pantheon.upstream.yml

