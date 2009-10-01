module SimplyStored
  module Storage
    module InstanceMethods
      def _s3_options
        self.class._s3_options
      end
      
      def s3_connection(name)
        @_s3_connection ||= RightAws::S3.new(_s3_options[name][:access_key], _s3_options[name][:secret_access_key], :multi_thread => true)
      end
    
      def s3_bucket(name)
        if !@_s3_bucket
          @_s3_bucket = s3_connection(name).bucket(_s3_options[name][:bucket])
          @_s3_bucket = s3_connection(name).bucket(_s3_options[name][:bucket], true, 'private') if @_s3_bucket.nil?
        end
        @_s3_bucket
      rescue Exception => e
        raise ArgumentError, "Could not access/create S3 bucket '#{name}': #{e} #{e.backtrace.join("\n")}"
      end
    
      def save(validate = true)
        if ret = super(validate)
          save_attachments
        end
        ret
      end
    
      def save_attachments
        if @_s3_attachments
          @_s3_attachments.each do |name, attachment|
            if attachment[:dirty]
              value = attachment[:value].is_a?(String) ? attachment[:value] : attachment[:value].to_json
              s3_bucket(name).put(s3_attachment_key(name), value, {}, _s3_options[name][:permissions])
              attachment[:dirty] = false
            end
          end
        end
      end
    
      def s3_attachment_key(name)
        "#{self.class.name.tableize}/#{name}/#{id}"
      end
    end
    
    module ClassMethods
      def has_s3_attachment(name, options = {})
        require 'awsbase/right_awsbase'
        require 's3/right_s3'
        require 's3/right_s3_interface'
        
        self.class.instance_eval do
          attr_accessor :_s3_options
        end
        
        name = name.to_sym
        raise ArgumentError, "No bucket name specified for attachment #{name}" if options[:bucket].blank?
        options.update(:permissions => 'private', :ssl => true)
        self._s3_options ||= {}
        self._s3_options[name] = options
        
        define_attachment_accessors(name)
        attr_reader :_s3_attachments
        include InstanceMethods
      end
      
      def define_attachment_accessors(name)
        define_method(name) do
          unless @_s3_attachments and @_s3_attachments[name]
            @_s3_attachments = {name => {}}
            @_s3_attachments[name][:value] = s3_bucket(name).get(s3_attachment_key(name))
          end
          @_s3_attachments[name][:value]
        end
        
        define_method("#{name}=") do |value|
          @_s3_attachments ||= {}
          @_s3_attachments[name] ||= {}
          @_s3_attachments[name].update(:value => value, :dirty => true)
          value
        end
        
        define_method("#{name}_url") do
          if _s3_options[name][:permissions] == 'private'
            RightAws::S3Generator.new(_s3_options[name][:access_key], _s3_options[name][:secret_access_key], :multi_thread => true).bucket(_s3_options[name][:bucket]).get(s3_attachment_key(name), 5.minutes)
          else
            "http://#{_s3_options[name][:bucket].to_s}.s3.amazonaws.com/#{s3_attachment_key(name)}"
          end
        end
      end
    end
  end
end