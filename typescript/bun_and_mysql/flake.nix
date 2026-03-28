{
  description = "Dashboard Analytics Platform - Development Environment";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bun
            nodejs
            mysql80
            curl
            jq
            git
          ];
          
          shellHook = ''
            export PROJECT_ROOT=$(pwd)
            export MYSQL_HOME=$PROJECT_ROOT/.mysql
            export MYSQL_DATADIR=$MYSQL_HOME/data
            export MYSQL_UNIX_PORT=$MYSQL_HOME/mysql.sock
            export MYSQL_PID_FILE=$MYSQL_HOME/mysql.pid
            
            # Add node_modules/.bin to PATH
            export PATH="$PROJECT_ROOT/node_modules/.bin:$PATH"
            
            # Set up cleanup trap - this runs when the shell exits
            _cleanup_on_exit() {
              echo ""
              echo "👋 Exiting development shell..."
              
              # Stop MySQL if it's running
              if [ -f "$MYSQL_PID_FILE" ] && kill -0 $(cat "$MYSQL_PID_FILE") 2>/dev/null; then
                echo "🛑 Stopping MySQL server..."
                mysqladmin shutdown --socket="$MYSQL_UNIX_PORT" 2>/dev/null || true
                
                # Wait a moment for graceful shutdown
                sleep 1
                
                # Force kill if still running
                if [ -f "$MYSQL_PID_FILE" ] && kill -0 $(cat "$MYSQL_PID_FILE") 2>/dev/null; then
                  echo "   Force stopping MySQL..."
                  kill -9 $(cat "$MYSQL_PID_FILE") 2>/dev/null || true
                fi
                
                echo "✓ MySQL stopped"
              fi
              
              echo "✓ Environment cleaned up"
              echo ""
            }
            
            # Register the cleanup function to run on exit
            trap _cleanup_on_exit EXIT
            
            # Create MySQL directories if they don't exist
            mkdir -p $MYSQL_DATADIR
            mkdir -p $MYSQL_HOME/tmp
            mkdir -p $MYSQL_HOME/log
            
            # Initialize MySQL data directory if it doesn't exist
            if [ ! -d "$MYSQL_DATADIR/mysql" ]; then
              echo "📦 Initializing MySQL data directory..."
              mysqld --initialize-insecure \
                --datadir=$MYSQL_DATADIR \
                --basedir=${pkgs.mysql80}
              echo "✓ MySQL initialized (no root password)"
            fi
            
            # Create MySQL config file
            cat > $MYSQL_HOME/my.cnf <<EOF
[mysqld]
datadir=$MYSQL_DATADIR
socket=$MYSQL_UNIX_PORT
pid-file=$MYSQL_PID_FILE
port=3306
bind-address=127.0.0.1
tmpdir=$MYSQL_HOME/tmp
log-error=$MYSQL_HOME/log/error.log

# Performance settings for development
max_connections=50
key_buffer_size=16M
max_allowed_packet=16M
table_open_cache=64
sort_buffer_size=512K
net_buffer_length=8K
read_buffer_size=256K
read_rnd_buffer_size=512K
myisam_sort_buffer_size=8M

# Character set
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

[client]
socket=$MYSQL_UNIX_PORT
port=3306
user=root
EOF
            
            # Define helper functions
            mysql-start() {
              if [ -f "$MYSQL_PID_FILE" ] && kill -0 $(cat "$MYSQL_PID_FILE") 2>/dev/null; then
                echo "⚠️  MySQL is already running (PID: $(cat $MYSQL_PID_FILE))"
                return 1
              fi
              
              echo "🚀 Starting MySQL server..."
              mysqld --defaults-file=$MYSQL_HOME/my.cnf &
              
              # Wait for MySQL to be ready
              for i in {1..30}; do
                if mysqladmin ping --socket=$MYSQL_UNIX_PORT >/dev/null 2>&1; then
                  echo "✓ MySQL is ready!"
                  return 0
                fi
                sleep 1
              done
              echo "❌ MySQL failed to start. Check $MYSQL_HOME/log/error.log"
              return 1
            }
            
            mysql-stop() {
              if [ ! -f "$MYSQL_PID_FILE" ]; then
                echo "⚠️  MySQL is not running"
                return 1
              fi
              
              echo "🛑 Stopping MySQL server..."
              mysqladmin shutdown --socket=$MYSQL_UNIX_PORT
              echo "✓ MySQL stopped"
            }
            
            mysql-status() {
              if [ -f "$MYSQL_PID_FILE" ] && kill -0 $(cat "$MYSQL_PID_FILE") 2>/dev/null; then
                echo "✓ MySQL is running (PID: $(cat $MYSQL_PID_FILE))"
                mysqladmin status --socket=$MYSQL_UNIX_PORT
              else
                echo "⚠️  MySQL is not running"
              fi
            }
            
            mysql-console() {
              mysql --socket=$MYSQL_UNIX_PORT "$@"
            }
            
            mysql-cleanup() {
              echo "🧹 Cleaning up MySQL processes..."
              
              # Try graceful shutdown first
              if pkill mysqld; then
                echo "   Sent shutdown signal to MySQL processes"
                sleep 2
              fi
              
              # Force kill any remaining processes
              if pkill -9 mysqld 2>/dev/null; then
                echo "   Force killed remaining MySQL processes"
              fi
              
              # Clean up PID files
              rm -f "$MYSQL_HOME"/*.pid
              
              echo "✓ Cleanup complete. You can now run mysql-start"
            }
            
            echo ""
            echo "🚀 Dashboard Analytics Platform - Dev Environment"
            echo ""
            echo "Available tools:"
            echo "  - Bun:     $(bun --version)"
            echo "  - Node:    $(node --version)"
            echo "  - MySQL:   $(mysql --version | head -n1)"
            echo ""
            echo "MySQL Configuration:"
            echo "  - Data directory: $MYSQL_DATADIR"
            echo "  - Socket: $MYSQL_UNIX_PORT"
            echo "  - Port: 3306"
            echo ""
            echo "MySQL Helper Commands:"
            echo "  - mysql-start     : Start MySQL server"
            echo "  - mysql-stop      : Stop MySQL server"
            echo "  - mysql-status    : Check MySQL status"
            echo "  - mysql-console   : Connect to MySQL CLI"
            echo "  - mysql-cleanup   : Clean up stuck MySQL processes"
            echo ""
            
            # Install dependencies if needed
            if [ -f bun.lockb ]; then
              echo "📦 Installing dependencies..."
              bun install --frozen-lockfile
            fi
            
            echo ""
            echo "💡 Tip: MySQL will automatically stop when you exit this shell"
            echo ""
          '';
        };
      }
    );
}
