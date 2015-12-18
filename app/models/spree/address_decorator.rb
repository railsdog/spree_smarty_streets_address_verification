Spree::Address.class_eval do

  # Indicates if an address is a valid deliverable address. Can only validate
  # addresses in the United States. If the address is outside the United States
  # then an error is thrown.
  def deliverable_address?
    raise SpreeSmartyStreetsAddressVerification::UnsupportedAddress,
      'Cannot validate internationally' unless in_united_states?

    # Grab out the fields we need and wrap up in object
    address = SmartyStreets::StreetAddressRequest.new \
      street: address1.to_s, street2: address2.to_s, city: city.to_s,
      state: state_text.to_s, zipcode: zipcode.to_s, addressee: company.to_s

    begin
      address = SmartyStreets::StreetAddressApi.call address

      if address.empty?
        # The API returns a list of address since it can validate multiple
        # addresses at once. If the list is empty then the address did not
        # validate so just return false
        return false
      else
        # If the list is not empty grab the first one and normalize the address
        # fields so the normalized version is saved.
        address = address.first
        self.company = address.addressee
        self.address1 = combine %i(
          primary_number street_predirection street_name
          street_suffix street_postdirection
        ), address
        self.address2 = combine %i(secondary_designator secondary_number), address
        self.city = address.components.city_name
        self.state = Spree::State.find_by abbr: address.components.state_abbreviation
        self.zipcode = combine %i(zipcode plus4_code), address, '-'
        return true
      end
    rescue SmartyStreets::ApiError
      if $!.code == SmartyStreets::ApiError::BAD_INPUT
        # If address did not have required fields then treat as a
        # non-deliverable address.
        return false
      else
        # All other errors are configuration and availability issues that
        # should raise an exception so the ops team can respond
        raise
      end
    end
  end

  # Boolean to indicate if the address is in the United states
  def in_united_states?
    # Use iso_name since the Spree factory uses "United States of America" for
    # the name while the spree seed data uses "United States". It's possible
    # a store may even customize the name to something else. So iso_name
    # seems safer. Use `try` in case country is not set.
    country.try(:iso_name) == 'UNITED STATES'
  end

  private

  def automatically_validate_address?
    return false unless in_united_states?
    return false unless SpreeSmartyStreetsAddressVerification.enabled? self
    return true if address_validation_field_changed?
    not validated?
  end

  def address_validation_field_changed?
    return false if new_record? && validated?
    return true if new_record?
    (changed & %w(address1 address2 city zipcode company state_name)).any? ||
    (state.id != state_id_was) || (country.id != country_id_was)
  end

  # Adds an error to the address model if the address is not deliverable
  def check_address
    self.validated = deliverable_address?
    errors[:base] << Spree.t(:invalid_address) unless validated?
  end
  validate :check_address, if: :automatically_validate_address?

  def combine components, address, sep=' '
    components.collect do |method|
      address.components.public_send method
    end.reject(&:blank?) * sep
  end

end
