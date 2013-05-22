require 'serialport'
require 'logger'

module Hacklet
  class Dongle
    # logger - Optionally takes a Logger instance, the default is to log to
    #          STDOUT
    def initialize(logger=Logger.new(STDOUT))
      @logger = logger
    end

    # Public: Initializes a session so the client can request data.
    #
    # port - Optional string for configuring the serial port device.
    #
    # Returns nothing.
    def open_session(port='/dev/ttyUSB0')
      @serial = open_serial_port(port)
      begin
        @logger.info("Booting")
        boot
        boot_confirm
        @logger.info("Booting complete")
        @logger.info("Locking network")
        lock_network
        @logger.info("Locking complete")
        yield self
      ensure
        @serial.close
      end
    end

    # Public: Selects the network.
    #
    # This must be executed within an open session. I'm guessing it selects the
    # network.
    #
    # network_id - 2 byte identified for the network.
    #
    # Returns nothing.
    def select_network(network_id)
      require_session

      transmit(HandshakeRequest.new(:network_id => network_id))
      HandshakeResponse.read(receive(6))
    end

    # Public: Request stored samples.
    #
    # network_id - 2 byte identified for the network.
    # channel_id - 2 byte identified for the channel.
    #
    # Returns the Responses::Samples
    def request_samples(network_id, channel_id)
      require_session

      transmit(SamplesRequest.new(:network_id => network_id, :channel_id => channel_id))
      AckResponse.read(receive(6))
      buffer = receive(4)
      remaining_bytes = buffer.split(' ')[3].to_i(16)+1
      buffer += receive(remaining_bytes)
      SamplesResponse.read(buffer)
    end

  private
    # Private: Initializes the serial port
    #
    # Returns a SerialPort object.
    def open_serial_port
      SerialPort.new(port, 115200, 8, 1, SerialPort::NONE)
    end

    # Private: Initializes the dongle for communication
    #
    # Returns the BootResponse
    def boot
      transmit(BootRequest.new)
      BootResponse.read(receive(27))
    end

    # Private: Confirms that booting was successful?
    #
    # Not sure about this.
    #
    # Returns the BootConfirmResponse
    def boot_confirm
      transmit(BootConfirmRequest.new)
      BootConfirmResponse.read(receive(6))
    end

    # Private: Locks the network.
    #
    # Not sure from what but that's what the logs say.
    #
    # Returns the BootConfirmResponse
    def lock_network
      transmit(LockRequest.new)
      LockResponse.read(receive(6))
    end

    def transmit(command)
      @logger.debug("TX: #{unpack(command.to_binary_s).inspect}")
      @serial.write(command.to_binary_s) if @serial
    end

    def receive(bytes)
      if @serial
        response = @serial.read(bytes)
      else
        response = "\x0\x0\x0\x0"
      end
      @logger.debug("RX: #{unpack(response).inspect}")

      response
    end

    def unpack(message)
      message.unpack('H2'*message.size)
    end

    def require_session
      raise RuntimeError.new("Must be executed within an open session") unless @serial && !@serial.closed?
    end
  end
end
